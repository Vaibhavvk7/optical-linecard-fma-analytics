USE NokiaFMA;
GO

/* ---------- CLEAN RESET (recommended) ---------- */
DELETE FROM dbo.Fact_BurnInTelemetry;
DELETE FROM dbo.Fact_FieldReturn;
DELETE FROM dbo.Fact_TestRun;
DELETE FROM dbo.Dim_Unit;
DELETE FROM dbo.Dim_Station;
DELETE FROM dbo.Dim_SupplierLot;
DELETE FROM dbo.Dim_LineCard;
GO

/* ---------- BULK LOAD INTO STAGING (dims first) ---------- */
BULK INSERT dbo.Stage_LineCard
FROM '/var/opt/mssql/import/dim_linecard.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Stage_SupplierLot
FROM '/var/opt/mssql/import/dim_supplier_lot.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Stage_Station
FROM '/var/opt/mssql/import/dim_station.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

BULK INSERT dbo.Stage_Unit
FROM '/var/opt/mssql/import/dim_unit.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
GO

/* Facts staging */
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

/* ---------- INSERT INTO REAL DIM TABLES (identity auto-generated) ---------- */
INSERT INTO dbo.Dim_LineCard (product_family, hw_revision, fw_version, optics_type, data_rate_gbps)
SELECT product_family, hw_revision, fw_version, optics_type, data_rate_gbps
FROM dbo.Stage_LineCard;
GO

INSERT INTO dbo.Dim_SupplierLot (optic_vendor, pcb_vendor, lot_code, lot_date, country)
SELECT optic_vendor, pcb_vendor, lot_code, lot_date, country
FROM dbo.Stage_SupplierLot;
GO

INSERT INTO dbo.Dim_Station (station_name, station_type, calibration_date, site)
SELECT station_name, station_type, calibration_date, site
FROM dbo.Stage_Station;
GO

/* ---------- INSERT UNITS (depends on linecard_id and supplier_lot_id) ---------- */
/*
Important: dim_unit.csv already uses numeric IDs 1..N that match the generated
order of the CSVs. Since we insert linecards/lots in the same order as staging,
the identity IDs will align (1..N). That makes this stable.
*/
INSERT INTO dbo.Dim_Unit (unit_serial, linecard_id, supplier_lot_id, manufacturing_site, operator_id, build_date)
SELECT unit_serial, linecard_id, supplier_lot_id, manufacturing_site, operator_id, build_date
FROM dbo.Stage_Unit;
GO

/* ---------- INSERT FACTS (FK requires Dim_Unit exists) ---------- */
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

INSERT INTO dbo.Fact_FieldReturn (unit_serial, return_date, symptom_code, confirmed_failure_mode, repair_action, notes)
SELECT unit_serial, return_date, symptom_code, confirmed_failure_mode, repair_action, notes
FROM dbo.Stage_FieldReturn;
GO

INSERT INTO dbo.Fact_BurnInTelemetry (unit_serial, ts, temp_c, vcore_v, ripple_mv, ber_snapshot)
SELECT unit_serial, ts, temp_c, vcore_v, ripple_mv, ber_snapshot
FROM dbo.Stage_BurnInTelemetry;
GO

