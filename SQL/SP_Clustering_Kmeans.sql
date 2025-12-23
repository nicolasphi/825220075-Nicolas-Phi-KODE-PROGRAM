USE star_schema_pmb;
GO

IF OBJECT_ID('dbo.fact_kmeans_wilayah','U') IS NULL
BEGIN
  CREATE TABLE dbo.fact_kmeans_wilayah(
      tahun_from  INT NOT NULL,
      tahun_to    INT NOT NULL,
      k_optimal   INT NULL,
      silhouette  FLOAT NULL,
      chart_json  NVARCHAR(MAX) NULL,
      stats_html  NVARCHAR(MAX) NULL,
      created_at  DATETIME2(3) NOT NULL CONSTRAINT DF_fact_kmeans_wilayah_created DEFAULT SYSUTCDATETIME(),
      CONSTRAINT PK_fact_kmeans_wilayah PRIMARY KEY (tahun_from, tahun_to)
  );
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_KMeansWilayah_Silhouette_2017_2023
  @tahun_from INT = 2017,
  @tahun_to   INT = 2023
AS
BEGIN
  SET NOCOUNT ON;

  /* 1) Dataset mentah untuk Python */
  DECLARE @input NVARCHAR(MAX) =
  N'WITH base AS (
      SELECT
        wilayah = COALESCE(
                    NULLIF(LTRIM(RTRIM(fp.kd_wil)), ''''),
                    NULLIF(LTRIM(RTRIM(dw.kd_wil)), '''')
                  ),
        tahun      = w.tahun,
        id_sekolah = fp.id_sekolah,
        kd_gender  = UPPER(LTRIM(RTRIM(fp.kd_gender)))
      FROM dbo.fact_pmb fp
      JOIN dbo.dim_waktu    w  ON w.id_waktu = fp.id_waktu
      LEFT JOIN dbo.dim_wilayah dw ON dw.id_wil = fp.id_wil
      WHERE w.tahun BETWEEN ' + CONVERT(NVARCHAR(10), @tahun_from) + ' AND ' + CONVERT(NVARCHAR(10), @tahun_to) + '
  )
  SELECT
    kd_wil   = wilayah,
    tahun,
    id_sekolah,
    kd_gender
  FROM base
  WHERE wilayah IS NOT NULL';

  /* 2) Python (pandas lama friendly) */
  DECLARE @py NVARCHAR(MAX) = N'
import pandas as pd, numpy as np, json, sys
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.decomposition import PCA

pdv = getattr(pd, "__version__", "?")
npv = getattr(np, "__version__", "?")

df = InputDataSet.copy()

def empty_row(msg):
    chart = {"silhouette":{"ks":[2],"values":[0.0]},"scatter":[],"counts":[],"debug":{"reason":msg,"pd":pdv,"np":npv}}
    return pd.DataFrame([{
        "k_optimal":2, "silhouette":0.0,
        "chart_json": json.dumps(chart, separators=(",",":")),
        "stats_html": msg + " | pd=" + pdv + " np=" + npv
    }], columns=["k_optimal","silhouette","chart_json","stats_html"])

if df is None or df.empty:
    OutputDataSet = empty_row("no rows")
else:
    df["kd_wil"] = df["kd_wil"].astype(str)
    df["is_f"] = (df["kd_gender"].astype(str).str.upper() == "P").astype(int)

    # ----- AGG KOMPATIBLE: pisah-agg lalu merge -----
    g_total = df.groupby("kd_wil").size().reset_index(name="total_maba")
    g_years = df.groupby("kd_wil")["tahun"].nunique().reset_index(name="years_act")
    g_sch   = df.groupby("kd_wil")["id_sekolah"].nunique().reset_index(name="uniq_sch")
    g_f     = df.groupby("kd_wil")["is_f"].sum().reset_index(name="total_f")

    g = g_total.merge(g_years, on="kd_wil", how="left") \
               .merge(g_sch,   on="kd_wil", how="left") \
               .merge(g_f,     on="kd_wil", how="left")
    g[["years_act","uniq_sch","total_f"]] = g[["years_act","uniq_sch","total_f"]].fillna(0)

    if g.shape[0] < 2:
        OutputDataSet = empty_row("insufficient rows")
    else:
        g["uniq_sch_safe"]  = np.maximum(1, g["uniq_sch"].astype(int))
        g["avg_per_sch"]    = g["total_maba"] / g["uniq_sch_safe"]

        # fitur: volume, cakupan, intensitas
        X0 = np.column_stack([
            np.log1p(g["total_maba"].astype(float).values),
            np.log1p(g["uniq_sch_safe"].astype(float).values),
            np.log1p(g["avg_per_sch"].astype(float).values)
        ])
        X = RobustScaler(quantile_range=(10,90)).fit_transform(X0)

        W = X.shape[0]
        kmax = int(min(8, max(2, W-1)))
        ks, sils = [], []
        best = None
        for k in range(2, kmax+1):
            km = KMeans(n_clusters=k, init="k-means++", n_init=25, random_state=42).fit(X)
            labels = km.labels_
            counts = np.bincount(labels, minlength=k)
            if counts.min() < 2:
                continue
            sil = float(silhouette_score(X, labels)) if len(np.unique(labels)) > 1 else 0.0
            ks.append(int(k)); sils.append(float(max(0.0, sil)))
            if (best is None) or (sil > best[0]):
                best = (sil, k, labels)

        if best is None:
            k = 2
            km = KMeans(n_clusters=k, init="k-means++", n_init=25, random_state=42).fit(X)
            labels = km.labels_
            sil = float(silhouette_score(X, labels)) if len(np.unique(labels)) > 1 else 0.0
        else:
            sil, k, labels = best

        # PCA untuk scatter
        p2 = PCA(n_components=2, random_state=42).fit_transform(X)

        # info tambahan
        g["female_share"] = np.where(g["total_maba"]>0, g["total_f"]/g["total_maba"], np.nan)

        scatter = []
        for cid in sorted(np.unique(labels)):
            idx = np.where(labels == cid)[0]
            pts = []
            for i in idx:
                pts.append({
                    "x": float(p2[i,0]),
                    "y": float(p2[i,1]),
                    "label": str(g.loc[i,"kd_wil"]),
                    "totalCnt": int(g.loc[i,"total_maba"]),
                    "femaleShare": (None if pd.isna(g.loc[i,"female_share"]) else float(g.loc[i,"female_share"])),
                    "uniqSchool": int(g.loc[i,"uniq_sch_safe"]),
                    "avgPerSchool": float(g.loc[i,"avg_per_sch"])
                })
            scatter.append({"label": "Klaster " + str(int(cid)+1), "data": pts})

        chart = {
            "silhouette": {"ks": ks, "values": sils},
            "scatter": scatter,
            "counts": [int((labels==c).sum()) for c in sorted(np.unique(labels))],
            "debug": {"reason":"ok","W":int(W), "pd":pdv, "np":npv}
        }
        row = {
            "k_optimal": int(k),
            "silhouette": float(max(0.0, sil)),
            "chart_json": json.dumps(chart, separators=(",",":")),
            "stats_html": "K optimal=" + str(int(k)) + "; Silhouette=" + ("%.3f" % float(max(0.0, sil))) + " | pd=" + pdv + " np=" + npv
        }
        OutputDataSet = pd.DataFrame([row], columns=["k_optimal","silhouette","chart_json","stats_html"])
';

  /* 3) Eksekusi Python */
  IF OBJECT_ID('tempdb..#py_out') IS NOT NULL DROP TABLE #py_out;
  CREATE TABLE #py_out(
      k_optimal  INT,
      silhouette FLOAT,
      chart_json NVARCHAR(MAX),
      stats_html NVARCHAR(MAX)
  );

  INSERT INTO #py_out (k_optimal, silhouette, chart_json, stats_html)
  EXEC sp_execute_external_script
       @language     = N'Python',
       @script       = @py,
       @input_data_1 = @input;

  IF NOT EXISTS (SELECT 1 FROM #py_out)
  BEGIN
    INSERT INTO #py_out (k_optimal, silhouette, chart_json, stats_html)
    VALUES (2, 0.0,
      N'{"silhouette":{"ks":[2],"values":[0.0]},"scatter":[],"counts":[],"debug":{"reason":"python no rows"}}',
      N'python no rows');
  END

  /* 4) Upsert */
  MERGE dbo.fact_kmeans_wilayah AS tgt
  USING (
    SELECT @tahun_from AS tahun_from, @tahun_to AS tahun_to,
           k_optimal, silhouette, chart_json, stats_html
    FROM #py_out
  ) AS src
  ON (tgt.tahun_from = src.tahun_from AND tgt.tahun_to = src.tahun_to)
  WHEN MATCHED THEN
    UPDATE SET k_optimal = src.k_optimal,
               silhouette = src.silhouette,
               chart_json = src.chart_json,
               stats_html = src.stats_html,
               created_at = SYSUTCDATETIME()
  WHEN NOT MATCHED THEN
    INSERT (tahun_from, tahun_to, k_optimal, silhouette, chart_json, stats_html, created_at)
    VALUES (src.tahun_from, src.tahun_to, src.k_optimal, src.silhouette, src.chart_json, src.stats_html, SYSUTCDATETIME());

  SELECT k_optimal, silhouette, chart_json, stats_html FROM #py_out;
END
GO
