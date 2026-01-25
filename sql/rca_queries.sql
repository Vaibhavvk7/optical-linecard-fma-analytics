USE NokiaFMA;
GO

/* =========================================================
RCA #1: Station drift ↔ NFF linkage (false-fail validation)
========================================================= */
WITH drift_stations AS (
  SELECT station_id
  FROM dbo.Dim_Station
  WHERE calibration_date < '2024-02-01'
),
nff_units AS (
  SELECT DISTINCT unit_serial
  FROM dbo.Fact_FieldReturn
  WHERE repair_action = 'NFF'
),
failed_events AS (
  SELECT
    tr.unit_serial,
    tr.station_id
  FROM dbo.Fact_TestRun tr
  WHERE tr.pass_fail = 0
)
SELECT
  CASE WHEN ds.station_id IS NULL THEN 'NON_DRIFT_STATION' ELSE 'DRIFT_STATION' END AS station_bucket,
  COUNT(*) AS failed_test_events,
  SUM(CASE WHEN nu.unit_serial IS NOT NULL THEN 1 ELSE 0 END) AS nff_linked_events,
  CAST(100.0 * SUM(CASE WHEN nu.unit_serial IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(5,2)) AS nff_link_rate_pct
FROM failed_events fe
LEFT JOIN drift_stations ds ON ds.station_id = fe.station_id
LEFT JOIN nff_units nu ON nu.unit_serial = fe.unit_serial
GROUP BY CASE WHEN ds.station_id IS NULL THEN 'NON_DRIFT_STATION' ELSE 'DRIFT_STATION' END
ORDER BY nff_link_rate_pct DESC;
GO


/* =========================================================
RCA #2: Driver strength table (fail rate when present vs absent)
========================================================= */
WITH base AS (
  SELECT
    tr.pass_fail,
    CASE WHEN tr.temp_c >= 75 THEN 1 ELSE 0 END AS high_temp,
    CASE WHEN tr.ripple_mv >= 35 THEN 1 ELSE 0 END AS high_ripple,
    CASE WHEN sl.optic_vendor = 'OptiCore' THEN 1 ELSE 0 END AS opti_vendor,
    CASE WHEN s.calibration_date < '2024-02-01' THEN 1 ELSE 0 END AS drift_station
  FROM dbo.Fact_TestRun tr
  JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
  JOIN dbo.Dim_SupplierLot sl ON sl.supplier_lot_id = u.supplier_lot_id
  JOIN dbo.Dim_Station s ON s.station_id = tr.station_id
),
agg AS (
  SELECT
    SUM(CASE WHEN high_temp=1 THEN 1 ELSE 0 END) AS n_high_temp,
    SUM(CASE WHEN high_temp=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_high_temp,
    SUM(CASE WHEN high_temp=0 THEN 1 ELSE 0 END) AS n_low_temp,
    SUM(CASE WHEN high_temp=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_low_temp,

    SUM(CASE WHEN high_ripple=1 THEN 1 ELSE 0 END) AS n_high_ripple,
    SUM(CASE WHEN high_ripple=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_high_ripple,
    SUM(CASE WHEN high_ripple=0 THEN 1 ELSE 0 END) AS n_low_ripple,
    SUM(CASE WHEN high_ripple=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_low_ripple,

    SUM(CASE WHEN opti_vendor=1 THEN 1 ELSE 0 END) AS n_opti,
    SUM(CASE WHEN opti_vendor=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_opti,
    SUM(CASE WHEN opti_vendor=0 THEN 1 ELSE 0 END) AS n_nonopti,
    SUM(CASE WHEN opti_vendor=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_nonopti,

    SUM(CASE WHEN drift_station=1 THEN 1 ELSE 0 END) AS n_drift,
    SUM(CASE WHEN drift_station=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_drift,
    SUM(CASE WHEN drift_station=0 THEN 1 ELSE 0 END) AS n_nondrift,
    SUM(CASE WHEN drift_station=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_nondrift
  FROM base
)
SELECT
  driver,
  CAST(fail_present AS DECIMAL(10,6)) AS fail_rate_when_present,
  CAST(fail_absent  AS DECIMAL(10,6)) AS fail_rate_when_absent,
  CAST((fail_present / NULLIF(fail_absent,0)) AS DECIMAL(10,3)) AS lift_ratio
FROM (
  SELECT
    'HIGH_TEMP' AS driver,
    (1.0 * f_high_temp / NULLIF(n_high_temp,0)) AS fail_present,
    (1.0 * f_low_temp  / NULLIF(n_low_temp,0))  AS fail_absent
  FROM agg
  UNION ALL
  SELECT
    'HIGH_RIPPLE',
    (1.0 * f_high_ripple / NULLIF(n_high_ripple,0)),
    (1.0 * f_low_ripple  / NULLIF(n_low_ripple,0))
  FROM agg
  UNION ALL
  SELECT
    'OPTIC_VENDOR_OPTICORE',
    (1.0 * f_opti / NULLIF(n_opti,0)),
    (1.0 * f_nonopti / NULLIF(n_nonopti,0))
  FROM agg
  UNION ALL
  SELECT
    'DRIFT_STATION',
    (1.0 * f_drift / NULLIF(n_drift,0)),
    (1.0 * f_nondrift / NULLIF(n_nondrift,0))
  FROM agg
) x
ORDER BY lift_ratio DESC;
GO


/* =========================================================
RCA #3: Fix-first list (lab fails → confirmed field returns)
========================================================= */
WITH fail_modes AS (
  SELECT failure_code, COUNT(*) AS fail_events
  FROM dbo.Fact_TestRun
  WHERE pass_fail=0 AND failure_code IS NOT NULL
  GROUP BY failure_code
),
returns_by_mode AS (
  SELECT
    confirmed_failure_mode AS failure_code,
    COUNT(*) AS returns
  FROM dbo.Fact_FieldReturn
  WHERE confirmed_failure_mode IS NOT NULL
  GROUP BY confirmed_failure_mode
)
SELECT
  fm.failure_code,
  fm.fail_events,
  ISNULL(rb.returns,0) AS confirmed_field_returns,
  CAST(100.0 * ISNULL(rb.returns,0) / NULLIF(fm.fail_events,0) AS DECIMAL(6,2)) AS return_to_fail_pct
FROM fail_modes fm
LEFT JOIN returns_by_mode rb ON rb.failure_code = fm.failure_code
ORDER BY confirmed_field_returns DESC, fm.fail_events DESC;
GO

