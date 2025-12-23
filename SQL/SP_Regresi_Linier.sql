USE star_schema_pmb;
GO

CREATE OR ALTER PROCEDURE dbo.sp_build_regresi_pmb
  @tahun_from   INT = 2017,
  @tahun_to     INT = 2023,
  @n_forecast   INT = 3,    -- berapa tahun ke depan
  @use_index_x  BIT = 1     -- 1: x = indeks tahun (1..N); 0: x = tahun asli
AS
BEGIN
  SET NOCOUNT ON;

  /* ---------- 1) Label tahun (termasuk forecast) ---------- */
  DECLARE @end_year INT = @tahun_to + @n_forecast;
  IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
  CREATE TABLE #L (th INT NOT NULL PRIMARY KEY);
  DECLARE @t INT = @tahun_from;
  WHILE @t <= @end_year
  BEGIN
    INSERT INTO #L(th) VALUES (@t);
    SET @t += 1;
  END

  /* ---------- 2) Aktual per tahun ---------- */
  IF OBJECT_ID('tempdb..#A') IS NOT NULL DROP TABLE #A;
  CREATE TABLE #A (th INT PRIMARY KEY, y INT);
  INSERT INTO #A(th,y)
  SELECT w.tahun, COUNT(*) AS y
  FROM star_schema_pmb.dbo.fact_pmb f
  JOIN star_schema_pmb.dbo.dim_waktu w ON w.id_waktu = f.id_waktu
  WHERE w.tahun BETWEEN @tahun_from AND @tahun_to
    AND f.kd_jur IS NOT NULL
  GROUP BY w.tahun;

  /* ---------- 3) Target per tahun ---------- */
  IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
  CREATE TABLE #T (th INT PRIMARY KEY, tgt INT);
  INSERT INTO #T(th,tgt)
  SELECT tahun, ISNULL(SUM(target_total),0)
  FROM Pmbregol.dbo.kpi_maba
  WHERE tahun BETWEEN @tahun_from AND @tahun_to
  GROUP BY tahun;

  /* ---------- 4) Seri lengkap ---------- */
  IF OBJECT_ID('tempdb..#S') IS NOT NULL DROP TABLE #S;
  CREATE TABLE #S (th INT, y INT, tgt INT, x INT);
  INSERT INTO #S(th,y,tgt,x)
  SELECT
    l.th,
    ISNULL(a.y,0)   AS y,
    ISNULL(t.tgt,0) AS tgt,
    CASE WHEN @use_index_x=1 THEN (l.th - @tahun_from + 1) ELSE l.th END AS x
  FROM #L AS l
  LEFT JOIN #A AS a ON a.th = l.th
  LEFT JOIN #T AS t ON t.th = l.th;

  /* ---------- 5) Data untuk fitting (ada aktual) ---------- */
  IF OBJECT_ID('tempdb..#SFIT') IS NOT NULL DROP TABLE #SFIT;
  SELECT th, y, x
  INTO #SFIT
  FROM #S
  WHERE th BETWEEN @tahun_from AND @tahun_to;

  /* ---------- 6) OLS: slope & intercept ---------- */
  DECLARE
      @n FLOAT, @sumX FLOAT, @sumY FLOAT, @sumXY FLOAT, @sumX2 FLOAT, @meanY FLOAT,
      @slope FLOAT, @intercept FLOAT;

  SELECT
      @n     = COUNT(*),
      @sumX  = SUM(CAST(x AS FLOAT)),
      @sumY  = SUM(CAST(y AS FLOAT)),
      @sumXY = SUM(CAST(x AS FLOAT) * CAST(y AS FLOAT)),
      @sumX2 = SUM(CAST(x AS FLOAT) * CAST(x AS FLOAT)),
      @meanY = AVG(CAST(y AS FLOAT))
  FROM #SFIT;

  DECLARE @num FLOAT = (@n*@sumXY - @sumX*@sumY);
  DECLARE @den FLOAT = (@n*@sumX2 - @sumX*@sumX);
  SET @slope     = CASE WHEN @den IS NULL OR @den = 0 THEN 0 ELSE @num/@den END;
  SET @intercept = CASE WHEN @n   IS NULL OR @n   = 0 THEN 0 ELSE (@sumY - @slope*@sumX)/@n END;

  /* ---------- 7) Metrik error ---------- */
  DECLARE @SSE FLOAT=0, @SST FLOAT=0, @MAE FLOAT=0, @RMSE FLOAT=0, @MAPE FLOAT=NULL, @R2 FLOAT=NULL;

  ;WITH ERR AS (
    SELECT
      th,
      y,
      yhat   = @intercept + @slope * x,
      absErr = ABS(CAST(y AS FLOAT) - (@intercept + @slope * x)),
      sqErr  = POWER(CAST(y AS FLOAT) - (@intercept + @slope * x), 2),
      yden   = NULLIF(CAST(y AS FLOAT), 0)
    FROM #SFIT
  )
  SELECT
      @SSE  = SUM(sqErr),
      @SST  = SUM(POWER(CAST(y AS FLOAT) - @meanY, 2)),
      @MAE  = AVG(absErr),
      @RMSE = SQRT(AVG(sqErr)),
      @MAPE = AVG(CASE WHEN yden IS NULL THEN NULL ELSE absErr / yden END) * 100.0
  FROM ERR;

  SET @R2 = CASE WHEN @SST IS NULL OR @SST = 0 THEN NULL ELSE 1.0 - (@SSE/@SST) END;

  /* ---------- 8) Array untuk Chart.js ---------- */
  DECLARE @labels        NVARCHAR(MAX);
  DECLARE @dataAktual    NVARCHAR(MAX);
  DECLARE @dataTarget    NVARCHAR(MAX);
  DECLARE @dataRegresi   NVARCHAR(MAX);
  DECLARE @dataForecastSeg NVARCHAR(MAX);
  DECLARE @dataForecastPts NVARCHAR(MAX);

  SELECT @labels =
    STRING_AGG('"' + CONVERT(varchar(10), th) + '"', ',') WITHIN GROUP (ORDER BY th)
  FROM #S;

  SELECT @dataAktual =
    STRING_AGG(CASE WHEN th BETWEEN @tahun_from AND @tahun_to
                    THEN CONVERT(varchar(32), y) ELSE 'null' END, ',')
    WITHIN GROUP (ORDER BY th)
  FROM #S;

  SELECT @dataTarget =
    STRING_AGG(CASE WHEN th BETWEEN @tahun_from AND @tahun_to
                    THEN CONVERT(varchar(32), tgt) ELSE 'null' END, ',')
    WITHIN GROUP (ORDER BY th)
  FROM #S;

  SELECT @dataRegresi =
    STRING_AGG(CONVERT(varchar(64), CAST(@intercept + @slope * x AS DECIMAL(18,2))), ',')
    WITHIN GROUP (ORDER BY th)
  FROM #S;

  SELECT @dataForecastSeg =
    STRING_AGG(CASE WHEN th >= @tahun_to
                    THEN CONVERT(varchar(64), CAST(@intercept + @slope * x AS DECIMAL(18,2)))
                    ELSE 'null' END, ',')
    WITHIN GROUP (ORDER BY th)
  FROM #S;

  SELECT @dataForecastPts =
    STRING_AGG(CASE WHEN th > @tahun_to
                    THEN CONVERT(varchar(64), CAST(@intercept + @slope * x AS DECIMAL(18,2)))
                    ELSE 'null' END, ',')
    WITHIN GROUP (ORDER BY th)
  FROM #S;

  /* ---------- 9) chart_json ---------- */
  DECLARE @chart_json NVARCHAR(MAX) =
  N'{"type":"line","data":{"labels":[' + @labels + N'],' +
    N'"datasets":[' +
      N'{"label":"Aktual","data":[' + @dataAktual + N'],"borderColor":"#3b82f6","backgroundColor":"#3b82f6","pointRadius":3,"borderWidth":2,"spanGaps":true},' +
      N'{"label":"Target","data":[' + @dataTarget + N'],"borderColor":"#6b7280","backgroundColor":"#6b7280","pointRadius":0,"borderWidth":2,"tension":0.15},' +
      N'{"label":"Regresi","data":[' + @dataRegresi + N'],"borderColor":"#ef4444","backgroundColor":"#ef4444","fill":false,"pointRadius":0,"tension":0.2,"borderWidth":2},' +
      N'{"label":"Segmen Forecast","data":[' + @dataForecastSeg + N'],"borderColor":"#ef4444","backgroundColor":"#ef4444","borderDash":[6,6],"pointRadius":0,"borderWidth":2},' +
      N'{"label":"Titik Prediksi","data":[' + @dataForecastPts + N'],"borderColor":"#ef4444","backgroundColor":"#ef4444","showLine":false,"pointRadius":4}' +
    N']},' +
    N'"options":{"responsive":true,"maintainAspectRatio":false,"plugins":{"legend":{"display":true}},"scales":{"y":{"beginAtZero":true}}}}';

  /* ---------- 10) stats_html ---------- */
  DECLARE
      @slope_txt     NVARCHAR(64) = CONVERT(varchar(50), CAST(@slope AS DECIMAL(18,6))),
      @intercept_txt NVARCHAR(64) = CONVERT(varchar(50), CAST(@intercept AS DECIMAL(18,3))),
      @r2_txt        NVARCHAR(32) = CONVERT(varchar(50), CAST(@R2 AS DECIMAL(18,3))),
      @mae_txt       NVARCHAR(32) = CONVERT(varchar(50), CAST(@MAE AS DECIMAL(18,0))),
      @rmse_txt      NVARCHAR(32) = CONVERT(varchar(50), CAST(@RMSE AS DECIMAL(18,0))),
      @mape_txt      NVARCHAR(32) = CONVERT(varchar(50), CAST(@MAPE AS DECIMAL(18,1)));

  DECLARE @stats_html NVARCHAR(MAX) =
    N'<p><b>Model:</b> y = α + β × x; y = jumlah pendaftar; x = ' +
    CASE WHEN @use_index_x = 1
         THEN N'(tahun − ' + CONVERT(varchar(10), @tahun_from) + N' + 1)'
         ELSE N'tahun'
    END + N'. ' +
    N'α=' + ISNULL(@intercept_txt,'-') + N', β=' + ISNULL(@slope_txt,'-') + N'. ' +
    N'R²=' + ISNULL(@r2_txt,'-') + N'; MAE=' + ISNULL(@mae_txt,'-') +
    N'; MAPE=' + ISNULL(@mape_txt,'-') + N'% ; RMSE=' + ISNULL(@rmse_txt,'-') + N'</p>';

  /* ---------- 11) Upsert ke fact_reg_tren ---------- */
  IF EXISTS (SELECT 1 FROM star_schema_pmb.dbo.fact_reg_tren
             WHERE tahun_from=@tahun_from AND tahun_to=@tahun_to)
    UPDATE star_schema_pmb.dbo.fact_reg_tren
      SET chart_json = @chart_json,
          stats_html = @stats_html,
          slope      = CAST(@slope AS DECIMAL(18,6)),
          intercept  = CAST(@intercept AS DECIMAL(18,6)),
          mae        = CAST(@MAE AS DECIMAL(18,6)),
          rmse       = CAST(@RMSE AS DECIMAL(18,6)),
          mape       = CAST(@MAPE AS DECIMAL(18,6)),
          r2         = CAST(@R2   AS DECIMAL(18,6)),
          created_at = SYSDATETIME()
    WHERE tahun_from=@tahun_from AND tahun_to=@tahun_to;
  ELSE
    INSERT INTO star_schema_pmb.dbo.fact_reg_tren
      (tahun_from, tahun_to, chart_json, stats_html,
       slope, intercept, mae, rmse, mape, r2, created_at)
    VALUES
      (@tahun_from, @tahun_to, @chart_json, @stats_html,
       CAST(@slope AS DECIMAL(18,6)), CAST(@intercept AS DECIMAL(18,6)),
       CAST(@MAE AS DECIMAL(18,6)), CAST(@RMSE AS DECIMAL(18,6)),
       CAST(@MAPE AS DECIMAL(18,6)), CAST(@R2 AS DECIMAL(18,6)),
       SYSDATETIME());
END
GO
