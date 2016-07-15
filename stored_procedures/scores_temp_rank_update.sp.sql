use QER
go

CREATE TABLE #SS_SECURITY (
  sector_id	int		NULL,
  segment_id	int		NULL,
  mqa_id	varchar(32)	NULL,
  ticker	varchar(16)	NULL,
  cusip		varchar(32)	NULL,
  sedol		varchar(32)	NULL,
  isin		varchar(64)	NULL,
  gv_key	int		NULL
)

CREATE TABLE #SCORES (
  cusip			varchar(32)	NOT NULL,
  sector_id		int		NULL,
  segment_id		int		NULL,
  sector_score		float		NULL,
  segment_score		float		NULL,
  ss_score		float		NULL,
  universe_score	float		NULL,
  total_score		float		NULL
)

IF OBJECT_ID('dbo.scores_temp_rank_update') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.scores_temp_rank_update
    IF OBJECT_ID('dbo.scores_temp_rank_update') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.scores_temp_rank_update >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.scores_temp_rank_update >>>'
END
go
CREATE PROCEDURE dbo.scores_temp_rank_update @BDATE datetime = NULL, --optional, defaults to previous business day
                                             @SCORE_TYPE varchar(16) = NULL, --required
                                             @STRATEGY_ID int = NULL, --required
                                             @DEBUG bit = NULL
AS

SELECT @SCORE_TYPE = UPPER(@SCORE_TYPE)

IF @SCORE_TYPE IS NULL OR (@SCORE_TYPE NOT IN ('SECTOR_SCORE','SEGMENT_SCORE','SS_SCORE','UNIVERSE_SCORE','TOTAL_SCORE'))
  BEGIN SELECT 'ERROR: @SCORE_TYPE PARAMETER MUST BE PASSED' RETURN -1 END
IF @STRATEGY_ID IS NULL
  BEGIN SELECT 'ERROR: @STRATEGY_ID PARAMETER MUST BE PASSED' RETURN -1 END

DECLARE @AGAINST varchar(1),
        @AGAINST_ID int,
        @FACTOR_ID int,
        @GROUPS int,
        @UNIVERSE_ID int,
        @RANK_EVENT_ID_MIN int,
        @RANK_EVENT_ID_MAX int

SELECT @GROUPS = fractile
  FROM strategy
 WHERE strategy_id = @STRATEGY_ID

IF @BDATE IS NULL
  BEGIN EXEC business_date_get @DIFF=-1, @RET_DATE=@BDATE OUTPUT END

SELECT @UNIVERSE_ID = universe_id
  FROM QER..strategy
 WHERE strategy_id = @STRATEGY_ID

SELECT @FACTOR_ID = factor_id
  FROM QER..factor
 WHERE factor_cd = 'DUMMY'

CREATE TABLE #DUMMY_FACTOR_STAGING (
  mqa_id	varchar(32)	NULL,
  ticker	varchar(16)	NULL,
  cusip		varchar(32)	NULL,
  sedol		varchar(32)	NULL,
  isin		varchar(64)	NULL,
  gv_key	int		NULL,
  factor_value	float		NULL
)

INSERT #DUMMY_FACTOR_STAGING
SELECT DISTINCT mqa_id, ticker, cusip, sedol, isin, gv_key,
       CASE @SCORE_TYPE WHEN 'SECTOR_SCORE' THEN sector_score
                        WHEN 'SEGMENT_SCORE' THEN segment_score
                        WHEN 'SS_SCORE' THEN ss_score
                        WHEN 'UNIVERSE_SCORE' THEN universe_score
                        WHEN 'TOTAL_SCORE' THEN total_score END
  FROM #SCORES

IF @DEBUG = 1
BEGIN
  SELECT '#SCORES'
  SELECT * FROM #SCORES ORDER BY cusip
  SELECT '#DUMMY_FACTOR_STAGING'
  SELECT * FROM #DUMMY_FACTOR_STAGING ORDER BY cusip, ticker
END

DELETE QER..instrument_factor_staging

INSERT QER..instrument_factor_staging
SELECT @BDATE, mqa_id, ticker, cusip, sedol, isin, gv_key, 'DUMMY', AVG(factor_value)
  FROM #DUMMY_FACTOR_STAGING
 GROUP BY mqa_id, ticker, cusip, sedol, isin, gv_key

IF @DEBUG = 1
BEGIN
  SELECT 'instrument_factor_staging'
  SELECT * FROM instrument_factor_staging ORDER BY cusip, ticker
END

DROP TABLE #DUMMY_FACTOR_STAGING

EXEC QER..instrument_factor_load @SOURCE_CD='FS'

IF @DEBUG = 1
BEGIN
  SELECT 'instrument_factor'
  SELECT * FROM instrument_factor WHERE bdate=@BDATE AND factor_id=@FACTOR_ID ORDER BY cusip, ticker
END

SELECT @RANK_EVENT_ID_MIN = max(rank_event_id) + 1
  FROM QER..rank_inputs

IF @SCORE_TYPE IN ('SECTOR_SCORE', 'SS_SCORE', 'SEGMENT_SCORE')
BEGIN
  CREATE TABLE #AGAINST_ID ( against_id int NOT NULL )

  IF @SCORE_TYPE IN ('SECTOR_SCORE', 'SS_SCORE')
  BEGIN
    SELECT @AGAINST = 'C'

    INSERT #AGAINST_ID
    SELECT DISTINCT sector_id
      FROM #SS_SECURITY
     WHERE sector_id IS NOT NULL
  END
  ELSE --('SEGMENT_SCORE')
  BEGIN
    SELECT @AGAINST = 'G'

    INSERT #AGAINST_ID
    SELECT DISTINCT segment_id
      FROM #SS_SECURITY
     WHERE segment_id IS NOT NULL
  END

  WHILE EXISTS (SELECT * FROM #AGAINST_ID)
  BEGIN
    SELECT @AGAINST_ID = min(against_id)
      FROM #AGAINST_ID

    EXEC rank_factor_universe @BDATE=@BDATE, @UNIVERSE_ID=@UNIVERSE_ID, @FACTOR_ID=@FACTOR_ID,
                              @GROUPS=@GROUPS, @AGAINST=@AGAINST, @AGAINST_ID=@AGAINST_ID, @DEBUG=@DEBUG

    DELETE #AGAINST_ID
     WHERE against_id = @AGAINST_ID
  END

  DROP TABLE #AGAINST_ID
END
ELSE --('UNIVERSE_SCORE', 'TOTAL_SCORE')
BEGIN
  EXEC rank_factor_universe @BDATE=@BDATE, @UNIVERSE_ID=@UNIVERSE_ID, @FACTOR_ID=@FACTOR_ID,
                            @GROUPS=@GROUPS, @AGAINST='U', @DEBUG=@DEBUG
END

SELECT @RANK_EVENT_ID_MAX = max(rank_event_id)
  FROM QER..rank_inputs

UPDATE #SCORES
   SET sector_score = CASE @SCORE_TYPE WHEN 'SECTOR_SCORE' THEN o.rank ELSE #SCORES.sector_score END,
       segment_score = CASE @SCORE_TYPE WHEN 'SEGMENT_SCORE' THEN o.rank ELSE #SCORES.segment_score END,
       ss_score = CASE @SCORE_TYPE WHEN 'SS_SCORE' THEN o.rank ELSE #SCORES.ss_score END,
       universe_score = CASE @SCORE_TYPE WHEN 'UNIVERSE_SCORE' THEN o.rank ELSE #SCORES.universe_score END,
       total_score = CASE @SCORE_TYPE WHEN 'TOTAL_SCORE' THEN o.rank ELSE #SCORES.total_score END
  FROM QER..rank_output o
 WHERE o.rank_event_id >= @RANK_EVENT_ID_MIN
   AND o.rank_event_id <= @RANK_EVENT_ID_MAX
   AND o.cusip = #SCORES.cusip

IF @DEBUG = 1
BEGIN
  SELECT '#SCORES'
  SELECT * FROM #SCORES ORDER BY cusip
END

EXEC QER..dummy_data_delete

RETURN 0
go
IF OBJECT_ID('dbo.scores_temp_rank_update') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.scores_temp_rank_update >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.scores_temp_rank_update >>>'
go

DROP TABLE #SCORES
DROP TABLE #SS_SECURITY