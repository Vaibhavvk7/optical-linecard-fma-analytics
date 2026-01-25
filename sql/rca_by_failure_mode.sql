USE NokiaFMA;
GO

/* =========================================================
Per-failure-mode RCA ranking (CORRECT VERSION)
Target:
  y = 1 → this specific failure_code
  y = 0 → pass OR other failure
========================================================= */

WITH base AS (
  SELECT
    tr.failure_code,
    CASE WHEN tr.failure_code IS NOT NULL THEN 1 ELSE 0 END AS any_fail,

    /* target flags (one-hot by failure mode) */
    CASE WHEN tr.failure_code = 'THERMAL_DRIFT' THEN 1 ELSE 0 END AS y_thermal,
    CASE WHEN tr.failure_code = 'VOLTAGE_RIPPLE' THEN 1 ELSE 0 END AS y_ripple,
    CASE WHEN tr.failure_code = 'OPTICS_DEGRADATION' THEN 1 ELSE 0 END AS y_optics,
    CASE WHEN tr.failure_code = 'STATION_FALSE_FAIL' THEN 1 ELSE 0 END AS y_station,
    CASE WHEN tr.failure_code = 'FW_REGRESSION' THEN 1 ELSE 0 END AS y_fw,

    /* drivers */
    CASE WHEN tr.temp_c >= 75 THEN 1 ELSE 0 END AS high_temp,
    CASE WHEN tr.ripple_mv >= 35 THEN 1 ELSE 0 END AS high_ripple,
    CASE WHEN s.calibration_date < '2024-02-01' THEN 1 ELSE 0 END AS drift_station,
    CASE WHEN sl.optic_vendor = 'OptiCore' THEN 1 ELSE 0 END AS opti_vendor
  FROM dbo.Fact_TestRun tr
  JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
  JOIN dbo.Dim_Station s ON s.station_id = tr.station_id
  JOIN dbo.Dim_SupplierLot sl ON sl.supplier_lot_id = u.supplier_lot_id
),

long_form AS (
  SELECT 'THERMAL_DRIFT' AS failure_code, high_temp, high_ripple, drift_station, opti_vendor, y_thermal AS y FROM base
  UNION ALL
  SELECT 'VOLTAGE_RIPPLE', high_temp, high_ripple, drift_station, opti_vendor, y_ripple FROM base
  UNION ALL
  SELECT 'OPTICS_DEGRADATION', high_temp, high_ripple, drift_station, opti_vendor, y_optics FROM base
  UNION ALL
  SELECT 'STATION_FALSE_FAIL', high_temp, high_ripple, drift_station, opti_vendor, y_station FROM base
  UNION ALL
  SELECT 'FW_REGRESSION', high_temp, high_ripple, drift_station, opti_vendor, y_fw FROM base
),

agg AS (
  SELECT
    failure_code,
    driver,
    SUM(CASE WHEN present=1 THEN 1 ELSE 0 END) AS n_present,
    SUM(CASE WHEN present=1 AND y=1 THEN 1 ELSE 0 END) AS f_present,
    SUM(CASE WHEN present=0 THEN 1 ELSE 0 END) AS n_absent,
    SUM(CASE WHEN present=0 AND y=1 THEN 1 ELSE 0 END) AS f_absent
  FROM (
    SELECT failure_code, 'HIGH_TEMP' AS driver, high_temp AS present, y FROM long_form
    UNION ALL
    SELECT failure_code, 'HIGH_RIPPLE', high_ripple, y FROM long_form
    UNION ALL
    SELECT failure_code, 'DRIFT_STATION', drift_station, y FROM long_form
    UNION ALL
    SELECT failure_code, 'OPTIC_VENDOR_OPTICORE', opti_vendor, y FROM long_form
  ) x
  GROUP BY failure_code, driver
)

SELECT
  failure_code,
  driver,
  n_present,
  CAST(1.0*f_present / NULLIF(n_present,0) AS DECIMAL(10,6)) AS fail_rate_present,
  n_absent,
  CAST(1.0*f_absent / NULLIF(n_absent,0) AS DECIMAL(10,6)) AS fail_rate_absent,
  CAST(
    (1.0*f_present / NULLIF(n_present,0)) /
    NULLIF((1.0*f_absent / NULLIF(n_absent,0)),0)
    AS DECIMAL(10,3)
  ) AS lift_ratio
FROM agg
WHERE n_present >= 500
ORDER BY failure_code, lift_ratio DESC;
GO


