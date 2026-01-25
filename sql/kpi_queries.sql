/* =========================================================
   KPI / RCA Queries for NokiaFMA (SQL Server)
   File: sql/kpi_queries.sql
   ========================================================= */
USE NokiaFMA;
GO

/* 1) Overall yield across all tests (pass rate) */
SELECT
    CAST(100.0 * SUM(CASE WHEN pass_fail = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS pass_rate_pct,
    COUNT(*) AS total_test_runs
FROM dbo.Fact_TestRun;

/* 2) Failure Pareto (Top 10 failure codes) */
SELECT TOP 10
    failure_code,
    COUNT(*) AS fail_count
FROM dbo.Fact_TestRun
WHERE pass_fail = 0 AND failure_code IS NOT NULL
GROUP BY failure_code
ORDER BY fail_count DESC;

/* 3) Pilot ramp: weekly failure rate (manufacturing view) */
WITH test_with_build AS (
    SELECT
        tr.test_run_id,
        u.build_date,
        tr.pass_fail
    FROM dbo.Fact_TestRun tr
    JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
)
SELECT
    DATEADD(WEEK, DATEDIFF(WEEK, 0, build_date), 0) AS build_week_start,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM test_with_build
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, build_date), 0)
ORDER BY build_week_start;

/* 4) Failure rate by HW revision + FW version */
SELECT
    lc.product_family,
    lc.hw_revision,
    lc.fw_version,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM dbo.Fact_TestRun tr
JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
JOIN dbo.Dim_LineCard lc ON lc.linecard_id = u.linecard_id
GROUP BY lc.product_family, lc.hw_revision, lc.fw_version
ORDER BY fail_rate_pct DESC, fails DESC;

/* 5) Failure rate by Supplier Lot (optic vendor / lot_code) */
SELECT
    sl.optic_vendor,
    sl.lot_code,
    sl.lot_date,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM dbo.Fact_TestRun tr
JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
JOIN dbo.Dim_SupplierLot sl ON sl.supplier_lot_id = u.supplier_lot_id
GROUP BY sl.optic_vendor, sl.lot_code, sl.lot_date
ORDER BY fail_rate_pct DESC, fails DESC;

/* 6) Station health: fail rate by station + calibration status */
SELECT
    s.station_name,
    s.station_type,
    s.calibration_date,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN tr.pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM dbo.Fact_TestRun tr
JOIN dbo.Dim_Station s ON s.station_id = tr.station_id
GROUP BY s.station_name, s.station_type, s.calibration_date
ORDER BY fail_rate_pct DESC, fails DESC;

/* 7) Pass vs Fail metric deltas (quick RCA hint) */
SELECT
    test_type,
    pass_fail,
    AVG(ber)          AS avg_ber,
    AVG(q_factor)     AS avg_q_factor,
    AVG(eye_height_mv) AS avg_eye_height_mv,
    AVG(ripple_mv)    AS avg_ripple_mv,
    AVG(temp_c)       AS avg_temp_c
FROM dbo.Fact_TestRun
GROUP BY test_type, pass_fail
ORDER BY test_type, pass_fail;

/* 8) High temperature risk: failure rate above temperature threshold */
DECLARE @temp_threshold FLOAT = 75.0;

SELECT
    CASE WHEN temp_c >= @temp_threshold THEN 'HIGH_TEMP' ELSE 'NORMAL_TEMP' END AS temp_bucket,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM dbo.Fact_TestRun
WHERE temp_c IS NOT NULL
GROUP BY CASE WHEN temp_c >= @temp_threshold THEN 'HIGH_TEMP' ELSE 'NORMAL_TEMP' END
ORDER BY fail_rate_pct DESC;

/* 9) Voltage ripple risk: failure rate above ripple threshold */
DECLARE @ripple_threshold FLOAT = 35.0;

SELECT
    CASE WHEN ripple_mv >= @ripple_threshold THEN 'HIGH_RIPPLE' ELSE 'NORMAL_RIPPLE' END AS ripple_bucket,
    COUNT(*) AS test_runs,
    SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) AS fails,
    CAST(100.0 * SUM(CASE WHEN pass_fail = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS fail_rate_pct
FROM dbo.Fact_TestRun
WHERE ripple_mv IS NOT NULL
GROUP BY CASE WHEN ripple_mv >= @ripple_threshold THEN 'HIGH_RIPPLE' ELSE 'NORMAL_RIPPLE' END
ORDER BY fail_rate_pct DESC;

/* 10) Field returns rate by supplier lot + NFF rate (station false-fail signal) */
WITH unit_returns AS (
    SELECT
        u.unit_serial,
        u.supplier_lot_id,
        fr.repair_action
    FROM dbo.Dim_Unit u
    LEFT JOIN dbo.Fact_FieldReturn fr
        ON fr.unit_serial = u.unit_serial
)
SELECT
    sl.optic_vendor,
    sl.lot_code,
    COUNT(*) AS units_built,
    SUM(CASE WHEN ur.unit_serial IS NOT NULL AND ur.repair_action IS NOT NULL THEN 1 ELSE 0 END) AS units_returned,
    CAST(100.0 * SUM(CASE WHEN ur.repair_action IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS field_return_rate_pct,
    SUM(CASE WHEN ur.repair_action = 'NFF' THEN 1 ELSE 0 END) AS nff_count,
    CAST(100.0 * SUM(CASE WHEN ur.repair_action = 'NFF' THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN ur.repair_action IS NOT NULL THEN 1 ELSE 0 END),0) AS DECIMAL(5,2)) AS nff_pct_of_returns
FROM dbo.Dim_SupplierLot sl
JOIN dbo.Dim_Unit u ON u.supplier_lot_id = sl.supplier_lot_id
LEFT JOIN unit_returns ur ON ur.unit_serial = u.unit_serial
GROUP BY sl.optic_vendor, sl.lot_code
ORDER BY field_return_rate_pct DESC;
GO

