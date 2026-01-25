USE NokiaFMA;
GO

/* ---------- Drop staging if rerunning ---------- */
IF OBJECT_ID('dbo.Stage_TestRun', 'U') IS NOT NULL DROP TABLE dbo.Stage_TestRun;
IF OBJECT_ID('dbo.Stage_FieldReturn', 'U') IS NOT NULL DROP TABLE dbo.Stage_FieldReturn;
IF OBJECT_ID('dbo.Stage_BurnInTelemetry', 'U') IS NOT NULL DROP TABLE dbo.Stage_BurnInTelemetry;
GO

/* ---------- Stage tables match CSV columns EXACTLY ---------- */
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

