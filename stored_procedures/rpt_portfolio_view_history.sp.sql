use QER
go
IF OBJECT_ID('dbo.rpt_portfolio_view_history') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.rpt_portfolio_view_history
    IF OBJECT_ID('dbo.rpt_portfolio_view_history') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.rpt_portfolio_view_history >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.rpt_portfolio_view_history >>>'
END
go
CREATE PROCEDURE dbo.rpt_portfolio_view_history
@BDATE datetime,
@STRATEGY_ID int,
@ACCOUNT_CD varchar(32),
@PERIODS int,
@PERIOD_TYPE varchar(2),
@DEBUG bit = NULL
AS
/* PORTFOLIO - RANKS */

IF @BDATE IS NULL
  BEGIN SELECT 'ERROR: @BDATE IS A REQUIRED PARAMETER' RETURN -1 END
IF @STRATEGY_ID IS NULL
  BEGIN SELECT 'ERROR: @STRATEGY_ID IS A REQUIRED PARAMETER' RETURN -1 END
IF @ACCOUNT_CD IS NULL
  BEGIN SELECT 'ERROR: @ACCOUNT_CD IS A REQUIRED PARAMETER' RETURN -1 END
IF @PERIODS IS NULL
  BEGIN SELECT 'ERROR: @PERIODS IS A REQUIRED PARAMETER' RETURN -1 END
IF @PERIODS > 0
  BEGIN SELECT @PERIODS = -1 * @PERIODS END
IF @PERIOD_TYPE IS NULL
  BEGIN SELECT 'ERROR: @PERIOD_TYPE IS A REQUIRED PARAMETER' RETURN -1 END
IF @PERIOD_TYPE NOT IN ('YY', 'YYYY', 'QQ', 'Q', 'MM', 'M', 'WK', 'WW', 'DD', 'D')
  BEGIN SELECT 'ERROR: INVALID VALUE PASSED FOR @PERIOD_TYPE PARAMETER' RETURN -1 END

CREATE TABLE #DATE (
  adate		datetime	NULL,
  bdate		datetime	NULL
)

INSERT #DATE (adate) VALUES (@BDATE)

WHILE (SELECT COUNT(*) FROM #DATE) < (ABS(@PERIODS)+1)
BEGIN
  IF @PERIOD_TYPE IN ('YY','YYYY')
    BEGIN INSERT #DATE (adate) SELECT DATEADD(YY, -1, MIN(adate)) FROM #DATE END
  ELSE IF @PERIOD_TYPE IN ('QQ','Q')
    BEGIN INSERT #DATE (adate) SELECT DATEADD(QQ, -1, MIN(adate)) FROM #DATE END
  ELSE IF @PERIOD_TYPE IN ('MM','M')
    BEGIN INSERT #DATE (adate) SELECT DATEADD(MM, -1, MIN(adate)) FROM #DATE END
  ELSE IF @PERIOD_TYPE IN ('WK','WW')
    BEGIN INSERT #DATE (adate) SELECT DATEADD(WK, -1, MIN(adate)) FROM #DATE END
  ELSE IF @PERIOD_TYPE IN ('DD','D')
    BEGIN INSERT #DATE (adate) SELECT DATEADD(DD, -1, MIN(adate)) FROM #DATE END
END

WHILE EXISTS (SELECT * FROM #DATE WHERE bdate IS NULL)
BEGIN
  SELECT @BDATE = MIN(adate) FROM #DATE WHERE bdate IS NULL

  EXEC business_date_get @DIFF=0, @REF_DATE=@BDATE, @RET_DATE=@BDATE OUTPUT

  IF @BDATE = (SELECT MIN(adate) FROM #DATE WHERE bdate IS NULL)
  BEGIN
    UPDATE #DATE
       SET bdate = adate
     WHERE adate = @BDATE
  END
  ELSE
  BEGIN
    SELECT @BDATE = MIN(adate) FROM #DATE WHERE bdate IS NULL

    EXEC business_date_get @DIFF=-1, @REF_DATE=@BDATE, @RET_DATE=@BDATE OUTPUT

    UPDATE #DATE
       SET bdate = @BDATE
     WHERE adate = (SELECT MIN(adate) FROM #DATE WHERE bdate IS NULL)
  END
END

IF @DEBUG = 1
BEGIN
  SELECT '#DATE'
  SELECT * FROM #DATE ORDER BY bdate, adate
END

CREATE TABLE #POSITION_SCORES (
  bdate			datetime	NULL,
  security_id	int			NULL,
  units			float		NULL,
  price			float		NULL,
  mval			float		NULL,
  weight		float		NULL,

  total_score		float	NULL,
  universe_score	float	NULL,
  region_score		float	NULL,
  country_score		float	NULL,
  ss_score			float	NULL,
  sector_score		float	NULL,
  segment_score		float	NULL,

  wgt_total			float	NULL,
  wgt_universe		float	NULL,
  wgt_region		float	NULL,
  wgt_country		float	NULL,
  wgt_ss			float	NULL,
  wgt_sector		float	NULL,
  wgt_segment		float	NULL
)

INSERT #POSITION_SCORES (bdate, security_id, units, price, weight)
SELECT reference_date, security_id, SUM(ISNULL(quantity,0.0)), 0.0, 0.0
  FROM equity_common..position
 WHERE reference_date IN (SELECT DISTINCT bdate FROM #DATE WHERE bdate >= (SELECT MIN(bdate) FROM scores WHERE strategy_id = @STRATEGY_ID))
   AND reference_date = effective_date
   AND acct_cd IN (SELECT acct_cd FROM equity_common..account WHERE parent = @ACCOUNT_CD
                   UNION
                   SELECT acct_cd FROM equity_common..account WHERE acct_cd = @ACCOUNT_CD)
 GROUP BY reference_date, security_id

UPDATE #POSITION_SCORES
   SET price = ISNULL(p.price_close_usd,0.0)
  FROM equity_common..market_price p
 WHERE #POSITION_SCORES.bdate = p.reference_date
   AND #POSITION_SCORES.security_id = p.security_id

UPDATE #POSITION_SCORES
   SET mval = units * price

UPDATE #POSITION_SCORES
   SET total_score = s.total_score,
       universe_score = s.universe_score,
       region_score = s.region_score,
       country_score = s.country_score,
       ss_score = s.ss_score,
       sector_score = s.sector_score,
       segment_score = s.segment_score
  FROM scores s
 WHERE #POSITION_SCORES.bdate = s.bdate
   AND s.strategy_id = @STRATEGY_ID
   AND #POSITION_SCORES.security_id = s.security_id

IF @DEBUG = 1
BEGIN
  SELECT '#POSITION_SCORES (1)'
  SELECT * FROM #POSITION_SCORES ORDER BY bdate, security_id
END

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE total_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.total_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_total = total_score * weight
 WHERE total_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE universe_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.universe_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_universe = universe_score * weight
 WHERE universe_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE region_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.region_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_region = region_score * weight
 WHERE region_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE country_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.country_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_country = country_score * weight
 WHERE country_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE ss_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.ss_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_ss = ss_score * weight
 WHERE ss_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE sector_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.sector_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_sector = sector_score * weight
 WHERE sector_score IS NOT NULL

UPDATE #POSITION_SCORES SET weight = 0.0

UPDATE #POSITION_SCORES
   SET weight = mval / x.tot_mval
  FROM (SELECT bdate, SUM(mval) AS tot_mval FROM #POSITION_SCORES
         WHERE segment_score IS NOT NULL GROUP BY bdate) x
 WHERE #POSITION_SCORES.bdate = x.bdate
   AND #POSITION_SCORES.segment_score IS NOT NULL
   AND x.tot_mval != 0.0

UPDATE #POSITION_SCORES
   SET wgt_segment = segment_score * weight
 WHERE segment_score IS NOT NULL

IF @DEBUG = 1
BEGIN
  SELECT '#POSITION_SCORES (2)'
  SELECT * FROM #POSITION_SCORES ORDER BY bdate, security_id
END

CREATE TABLE #RESULT (
  ordinal			int identity(1,1) NOT NULL,
  bdate				datetime	NULL,
  total_wgt_avg		float		NULL,
  total_median		float		NULL,
  universe_wgt_avg	float		NULL,
  universe_median	float		NULL,
  region_wgt_avg	float		NULL,
  region_median		float		NULL,
  country_wgt_avg	float		NULL,
  country_median	float		NULL,
  ss_wgt_avg		float		NULL,
  ss_median			float		NULL,
  sector_wgt_avg	float		NULL,
  sector_median		float		NULL,
  segment_wgt_avg	float		NULL,
  segment_median	float		NULL
)

INSERT #RESULT (bdate, total_wgt_avg, universe_wgt_avg, region_wgt_avg, country_wgt_avg, ss_wgt_avg, sector_wgt_avg, segment_wgt_avg)
SELECT bdate, SUM(wgt_total), SUM(wgt_universe), SUM(wgt_region), SUM(wgt_country), SUM(wgt_ss), SUM(wgt_sector), SUM(wgt_segment)
  FROM #POSITION_SCORES
 GROUP BY bdate
 ORDER BY bdate

IF @DEBUG = 1
BEGIN
  SELECT '#RESULT (1)'
  SELECT * FROM #RESULT ORDER BY bdate
END

CREATE TABLE #TEMP (
  ordinal	int identity(1,1)	NOT NULL,
  score		float				NOT NULL
)

DECLARE
@ORDINAL int,
@MEDIAN_SCORE float

SELECT @ORDINAL = 0
WHILE EXISTS (SELECT 1 FROM #RESULT WHERE ordinal > @ORDINAL)
BEGIN
  SELECT @ORDINAL = MIN(ordinal) FROM #RESULT WHERE ordinal > @ORDINAL
  SELECT @BDATE = bdate FROM #RESULT where ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT total_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND total_score IS NOT NULL
   ORDER BY total_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET total_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT universe_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND universe_score IS NOT NULL
   ORDER BY universe_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET universe_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT region_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND region_score IS NOT NULL
   ORDER BY region_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET region_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT country_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND country_score IS NOT NULL
   ORDER BY country_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET country_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT ss_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND ss_score IS NOT NULL
   ORDER BY ss_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET ss_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT sector_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND sector_score IS NOT NULL
   ORDER BY sector_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET sector_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL

  SELECT @MEDIAN_SCORE = NULL
  TRUNCATE TABLE #TEMP

  INSERT #TEMP (score)
  SELECT segment_score FROM #POSITION_SCORES
   WHERE bdate = @BDATE AND segment_score IS NOT NULL
   ORDER BY segment_score

  IF (SELECT MAX(ordinal) FROM #TEMP) % 2 = 0
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE + score FROM #TEMP WHERE ordinal = (SELECT MAX(ordinal)/2.0 + 1 FROM #TEMP)
    SELECT @MEDIAN_SCORE = @MEDIAN_SCORE / 2.0
  END
  ELSE
  BEGIN
    SELECT @MEDIAN_SCORE = score FROM #TEMP WHERE ordinal = CEILING((SELECT MAX(ordinal) FROM #TEMP)/2.0)
  END

  UPDATE #RESULT SET segment_median = @MEDIAN_SCORE WHERE ordinal = @ORDINAL
END

DROP TABLE #TEMP

INSERT #RESULT (bdate)
SELECT DISTINCT bdate
  FROM #DATE d
 WHERE NOT EXISTS (SELECT 1 FROM #RESULT r WHERE d.bdate = r.bdate)
   AND d.bdate >= (SELECT MIN(bdate) FROM scores WHERE strategy_id = @STRATEGY_ID)

IF @DEBUG = 1
BEGIN
  SELECT '#RESULT (2)'
  SELECT * FROM #RESULT ORDER BY bdate
END

SELECT bdate			AS [Date],
       total_wgt_avg	AS [Total Wgt Avg],
       total_median		AS [Total Median],
       universe_wgt_avg	AS [Universe Wgt Avg],
       universe_median	AS [Universe Median],
       region_wgt_avg	AS [Region Wgt Avg],
       region_median	AS [Region Median],
       country_wgt_avg	AS [Country Wgt Avg],
       country_median	AS [Country Median],
       ss_wgt_avg		AS [SS Wgt Avg],
       ss_median		AS [SS Median],
       sector_wgt_avg	AS [Sector Wgt Avg],
       sector_median	AS [Sector Median],
       segment_wgt_avg	AS [Segment Wgt Avg],
       segment_median	AS [Segment Median]
  FROM #RESULT
 ORDER BY bdate DESC

DROP TABLE #RESULT
DROP TABLE #POSITION_SCORES
DROP TABLE #DATE

RETURN 0
go
IF OBJECT_ID('dbo.rpt_portfolio_view_history') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.rpt_portfolio_view_history >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.rpt_portfolio_view_history >>>'
go
