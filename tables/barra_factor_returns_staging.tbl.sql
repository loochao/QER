use QER
go

create table dbo.barra_factor_returns_staging (
  DATE		datetime	not null,--key
  VOLTILTY	float		null,
  MOMENTUM	float		null,
  SIZE    	float		null,
  SIZENONL	float		null,
  TRADEACT	float		null,
  GROWTH  	float		null,
  EARNYLD 	float		null,
  VALUE   	float		null,
  EARNVAR 	float		null,
  LEVERAGE	float		null,
  CURRSEN 	float		null,
  YIELD   	float		null,
  NONESTU 	float		null,
  MINING  	float		null,
  GOLD    	float		null,
  FOREST  	float		null,
  CHEMICAL	float		null,
  ENGYRES 	float		null,
  OILREF  	float		null,
  OILSVCS 	float		null,
  FOODBEV 	float		null,
  ALCOHOL 	float		null,
  TOBACCO 	float		null,
  HOMEPROD	float		null,
  GROCERY 	float		null,
  CONSDUR 	float		null,
  MOTORVEH	float		null,
  APPAREL 	float		null,
  CLOTHING	float		null,
  SPLTYRET	float		null,
  DEPTSTOR	float		null,
  CONSTRUC	float		null,
  PUBLISH 	float		null,
  MEDIA   	float		null,
  HOTELS  	float		null,
  RESTRNTS	float		null,
  ENTRTAIN	float		null,
  LEISURE 	float		null,
  ENVSVCS 	float		null,
  HEAVYELC	float		null,
  HEAVYMCH	float		null,
  INDPART 	float		null,
  ELECUTIL	float		null,
  GASUTIL 	float		null,
  RAILROAD	float		null,
  AIRLINES	float		null,
  TRUCKFRT	float		null,
  MEDPROVR	float		null,
  MEDPRODS	float		null,
  DRUGS   	float		null,
  ELECEQP 	float		null,
  SEMICOND	float		null,
  CMPTRHW 	float		null,
  CMPTRSW 	float		null,
  DEFAERO 	float		null,
  TELEPHON	float		null,
  WIRELESS	float		null,
  INFOSVCS	float		null,
  INDSVCS 	float		null,
  LIFEINS 	float		null,
  PRPTYINS	float		null,
  BANKS   	float		null,
  THRIFTS 	float		null,
  SECASSET	float		null,
  FINSVCS 	float		null,
  INTERNET	float		null,
  EQTYREIT	float		null,
  BIOTECH	float		null
)
go
