USE NokiaFMA;
GO

/* ---------- Drop staging tables if rerunning ---------- */
IF OBJECT_ID('dbo.Stage_LineCard', 'U') IS NOT NULL DROP TABLE dbo.Stage_LineCard;
IF OBJECT_ID('dbo.Stage_SupplierLot', 'U') IS NOT NULL DROP TABLE dbo.Stage_SupplierLot;
IF OBJECT_ID('dbo.Stage_Station', 'U') IS NOT NULL DROP TABLE dbo.Stage_Station;
IF OBJECT_ID('dbo.Stage_Unit', 'U') IS NOT NULL DROP TABLE dbo.Stage_Unit;

IF OBJECT_ID('dbo.Stage_TestRun', 'U') IS NOT NULL DROP TABLE dbo.Stage_TestRun;
IF OBJECT_ID('dbo.Stage_FieldReturn', 'U') IS NOT NULL DROP TABLE dbo.Stage_FieldReturn;
IF OBJECT_ID('dbo.Stage_BurnInTelemetry', 'U') IS NOT NULL DROP TABLE dbo.Stage_BurnInTelemetry;
GO

/* ---------- Staging tables match CSV columns exactly ---------- */

CREATE TABLE dbo.Stage_LineCard (
    product_family  VARCHAR(64) NOT NULL,
    hw_revision     VARCHAR(32) NOT NULL,
    fw_version      VARCHAR(32) NOT NULL,
    optics_type     VARCHAR(16) NOT NULL,
    data_rate_gbps  INT NOT NULL
);
GO

CREATE TABLE dbo.Stage_SupplierLot (
    optic_vendor VARCHAR(64) NOT NULL,
    pcb_vendor   VARCHAR(64) NOT NULL,
    lot_code     VARCHAR(64) NOT NULL,
    lot_date     DATE NOT NULL,
    country      VARCHAR(64) NULL
);
GO

CREATE TABLE dbo.Stage_Station (
    station_name     VARCHAR(64) NOT NULL,
    station_type     VARCHAR(32) NOT NULL,
    calibration_date DATE NULL,
    site             VARCHAR(64) NULL
);
GO

CREATE TABLE dbo.Stage_Unit (
    unit_serial         VARCHAR(64) NOT NULL,
    linecard_id         INT NOT NULL,
    supplier_lot_id     INT NOT NULL,
    manufacturing_site  VARCHAR(64) NOT NULL,
    operator_id         VARCHAR(64) NULL,
    build_date          DATE NOT NULL
);
GO

/* Facts staging (same as before) */
CREATE TABLE dbo.Stage_TestRun (
    unit_serial       VARCHAR(64)  NOT NULL,
    station_id        INT          NOT NULL,
    test_type         VARCHAR(32)  NOT NULL,
    start_ts          DATETIME2(0) NOT NULL,
    end_ts            DATETIME2(0) NOT NULL,
    pass_fail         BIT          NOT NULL,
    failure_code      VARCHAR(64)  NULL,

    ber               FLOAT        NULL,
    q_factor          FLOAT        NULL,
    eye_height_mv     FLOAT        NULL,
    eye_width_ps      FLOAT        NULL,
    rx_power_dbm      FLOAT        NULL,
    tx_power_dbm      FLOAT        NULL,

    vcore_v           FLOAT        NULL,
    vaux_v            FLOAT        NULL,
    iin_a             FLOAT        NULL,
    ripple_mv         FLOAT        NULL,

    temp_c            FLOAT        NULL,
    humidity_pct      FLOAT        NULL
);
GO

CREATE TABLE dbo.Stage_FieldReturn (
    unit_serial            VARCHAR(64) NOT NULL,
    return_date            DATE        NOT NULL,
    symptom_code           VARCHAR(64) NOT NULL,
    confirmed_failure_mode VARCHAR(64) NULL,
    repair_action          VARCHAR(32) NOT NULL,
    notes                  VARCHAR(256) NULL
);
GO

CREATE TABLE dbo.Stage_BurnInTelemetry (
    unit_serial    VARCHAR(64)  NOT NULL,
    ts            DATETIME2(0) NOT NULL,
    temp_c        FLOAT        NULL,
    vcore_v       FLOAT        NULL,
    ripple_mv     FLOAT        NULL,
    ber_snapshot  FLOAT        NULL
);
GO

