USE NokiaFMA;
GO

/* ---------- Load dimensions (these match CSV columns) ---------- */
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

/* ---------- Bulk load to staging (NO identity columns) ---------- */
BULK INSERT dbo.Stage_TestRun
FROM '/var/opt/mssql/import/fact_testrun.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Stage_FieldReturn
FROM '/var/opt/mssql/import/fact_fieldreturn.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Stage_BurnInTelemetry
FROM '/var/opt/mssql/import/fact_burnin_telemetry.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* ---------- Insert into final fact tables (identity auto-generated) ---------- */
INSERT INTO dbo.Fact_TestRun (
    unit_serial, station_id, test_type, start_ts, end_ts, pass_fail, failure_code,
    ber, q_factor, eye_height_mv, eye_width_ps, rx_power_dbm, tx_power_dbm,
    vcore_v, vaux_v, iin_a, ripple_mv, temp_c, humidity_pct
)
SELECT
    unit_serial, station_id, test_type, start_ts, end_ts, pass_fail, failure_code,
    ber, q_factor, eye_height_mv, eye_width_ps, rx_power_dbm, tx_power_dbm,
    vcore_v, vaux_v, iin_a, ripple_mv, temp_c, humidity_pct
FROM dbo.Stage_TestRun;
GO

INSERT INTO dbo.Fact_FieldReturn (
    unit_serial, return_date, symptom_code, confirmed_failure_mode, repair_action, notes
)
SELECT
    unit_serial, return_date, symptom_code, confirmed_failure_mode, repair_action, notes
FROM dbo.Stage_FieldReturn;
GO

INSERT INTO dbo.Fact_BurnInTelemetry (
    unit_serial, ts, temp_c, vcore_v, ripple_mv, ber_snapshot
)
SELECT
    unit_serial, ts, temp_c, vcore_v, ripple_mv, ber_snapshot
FROM dbo.Stage_BurnInTelemetry;
GO

