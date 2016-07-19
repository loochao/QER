use QER
go
IF OBJECT_ID('dbo.russell_industry_get') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.russell_industry_get
    IF OBJECT_ID('dbo.russell_industry_get') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.russell_industry_get >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.russell_industry_get >>>'
END
go
CREATE PROCEDURE dbo.russell_industry_get
@BDATE datetime
AS

IF @BDATE IS NULL
  BEGIN SELECT 'ERROR: @BDATE IS A REQUIRED PARAMETER' RETURN -1 END

CREATE TABLE #RUSSELL_INDUSTRY (
  industry_id			int			NULL,
  russell_industry_num	int			NULL,
  russell_industry_nm	varchar(64)	NULL
)

INSERT #RUSSELL_INDUSTRY
SELECT DISTINCT NULL, y.russell_industry_num, UPPER(y.russell_industry_name)
  FROM equity_common..security y,
      (SELECT security_id FROM universe_makeup WHERE universe_dt = @BDATE
       UNION
       SELECT security_id FROM equity_common..position
        WHERE reference_date = @BDATE
          AND reference_date = effective_date
          AND acct_cd IN (SELECT DISTINCT a.acct_cd
                            FROM equity_common..account a,
                                (SELECT account_cd AS [account_cd] FROM account
                                 UNION
                                 SELECT benchmark_cd AS [account_cd] FROM benchmark) q
                           WHERE a.parent = q.account_cd OR a.acct_cd = q.account_cd)) x
 WHERE y.security_id = x.security_id
   AND y.russell_industry_num IS NOT NULL
   AND y.russell_industry_name IS NOT NULL

UPDATE #RUSSELL_INDUSTRY
   SET industry_id = i.industry_id
  FROM QER..industry_model m, QER..industry i
 WHERE m.industry_model_cd = 'RUSSELL-I'
   AND m.industry_model_id = i.industry_model_id
   AND i.industry_num = #RUSSELL_INDUSTRY.russell_industry_num

DELETE #RUSSELL_INDUSTRY
  FROM QER..industry i
 WHERE i.industry_id = #RUSSELL_INDUSTRY.industry_id
   AND i.industry_nm IS NOT NULL

UPDATE QER..industry
   SET industry_nm = r.russell_industry_nm
  FROM #RUSSELL_INDUSTRY r
 WHERE QER..industry.industry_id = r.industry_id
   AND QER..industry.industry_nm IS NULL

DELETE #RUSSELL_INDUSTRY
 WHERE industry_id IS NOT NULL

INSERT QER..industry (industry_model_id, industry_num, industry_nm)
SELECT m.industry_model_id, r.russell_industry_num, r.russell_industry_nm
  FROM QER..industry_model m, #RUSSELL_INDUSTRY r
 WHERE m.industry_model_cd = 'RUSSELL-I'

DROP TABLE #RUSSELL_INDUSTRY

RETURN 0
go
IF OBJECT_ID('dbo.russell_industry_get') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.russell_industry_get >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.russell_industry_get >>>'
go
