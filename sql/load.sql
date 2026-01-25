USE NokiaFMA;
GO

/* ---------- Dimensions ---------- */
BULK INSERT dbo.Dim_LineCard
FROM '/var/opt/mssql/import/dim_linecard.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Dim_SupplierLot
FROM '/var/opt/mssql/import/dim_supplier_lot.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Dim_Station
FROM '/var/opt/mssql/import/dim_station.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Dim_Unit
FROM '/var/opt/mssql/import/dim_unit.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* ---------- Facts ---------- */
BULK INSERT dbo.Fact_TestRun
FROM '/var/opt/mssql/import/fact_testrun.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Fact_FieldReturn
FROM '/var/opt/mssql/import/fact_fieldreturn.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Fact_BurnInTelemetry
FROM '/var/opt/mssql/import/fact_burnin_telemetry.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO
