/* =========================================================
   Nokia-style FMA Line Card Analytics Schema (SQL Server)
   Target: Local SQL Server
   File: sql/schema.sql
   ========================================================= */

-- Create DB (optional)
IF DB_ID('NokiaFMA') IS NULL
BEGIN
    CREATE DATABASE NokiaFMA;
END
GO

USE NokiaFMA;
GO

/* ---------- Safety: drop tables in dependency order (dev only) ---------- */
IF OBJECT_ID('dbo.Fact_BurnInTelemetry', 'U') IS NOT NULL DROP TABLE dbo.Fact_BurnInTelemetry;
IF OBJECT_ID('dbo.Fact_FieldReturn', 'U') IS NOT NULL DROP TABLE dbo.Fact_FieldReturn;
IF OBJECT_ID('dbo.Fact_TestRun', 'U') IS NOT NULL DROP TABLE dbo.Fact_TestRun;
IF OBJECT_ID('dbo.Dim_Unit', 'U') IS NOT NULL DROP TABLE dbo.Dim_Unit;
IF OBJECT_ID('dbo.Dim_Station', 'U') IS NOT NULL DROP TABLE dbo.Dim_Station;
IF OBJECT_ID('dbo.Dim_SupplierLot', 'U') IS NOT NULL DROP TABLE dbo.Dim_SupplierLot;
IF OBJECT_ID('dbo.Dim_LineCard', 'U') IS NOT NULL DROP TABLE dbo.Dim_LineCard;
GO

/* -------------------- Dimension tables -------------------- */

CREATE TABLE dbo.Dim_LineCard (
    linecard_id          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    product_family       VARCHAR(64)        NOT NULL,
    hw_revision          VARCHAR(32)        NOT NULL,
    fw_version           VARCHAR(32)        NOT NULL,
    optics_type          VARCHAR(16)        NOT NULL,   -- SR/LR/ER/etc.
    data_rate_gbps       INT                NOT NULL,   -- 100/400/etc.
    created_utc          DATETIME2(0)       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.Dim_SupplierLot (
    supplier_lot_id      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    optic_vendor         VARCHAR(64)        NOT NULL,
    pcb_vendor           VARCHAR(64)        NOT NULL,
    lot_code             VARCHAR(64)        NOT NULL,
    lot_date             DATE               NOT NULL,
    country              VARCHAR(64)        NULL,
    created_utc          DATETIME2(0)       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.Dim_Station (
    station_id           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    station_name         VARCHAR(64)        NOT NULL,
    station_type         VARCHAR(32)        NOT NULL,  -- ICT/FUNCTIONAL/BURNIN/OPTICAL
    calibration_date     DATE               NULL,
    site                 VARCHAR(64)        NULL,
    created_utc          DATETIME2(0)       NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.Dim_Unit (
    unit_serial          VARCHAR(64)        NOT NULL PRIMARY KEY,
    linecard_id          INT                NOT NULL,
    supplier_lot_id      INT                NOT NULL,
    manufacturing_site   VARCHAR(64)        NOT NULL,
    operator_id          VARCHAR(64)        NULL,
    build_date           DATE               NOT NULL,
    created_utc          DATETIME2(0)       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_Dim_Unit_LineCard
        FOREIGN KEY (linecard_id) REFERENCES dbo.Dim_LineCard(linecard_id),

    CONSTRAINT FK_Dim_Unit_SupplierLot
        FOREIGN KEY (supplier_lot_id) REFERENCES dbo.Dim_SupplierLot(supplier_lot_id)
);
GO

/* -------------------- Fact tables -------------------- */

CREATE TABLE dbo.Fact_TestRun (
    test_run_id          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    unit_serial          VARCHAR(64)          NOT NULL,
    station_id           INT                  NOT NULL,
    test_type            VARCHAR(32)          NOT NULL,   -- ICT/FUNCTIONAL/BURNIN/OPTICAL
    start_ts             DATETIME2(0)         NOT NULL,
    end_ts               DATETIME2(0)         NOT NULL,
    pass_fail            BIT                  NOT NULL,
    failure_code         VARCHAR(64)          NULL,

    -- Optical metrics
    ber                  FLOAT                NULL,  -- Bit Error Rate
    q_factor             FLOAT                NULL,
    eye_height_mv        FLOAT                NULL,
    eye_width_ps         FLOAT                NULL,
    rx_power_dbm         FLOAT                NULL,
    tx_power_dbm         FLOAT                NULL,

    -- Electrical metrics
    vcore_v              FLOAT                NULL,
    vaux_v               FLOAT                NULL,
    iin_a                FLOAT                NULL,
    ripple_mv            FLOAT                NULL,

    -- Environmental
    temp_c               FLOAT                NULL,
    humidity_pct         FLOAT                NULL,

    created_utc          DATETIME2(0)         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_Fact_TestRun_Unit
        FOREIGN KEY (unit_serial) REFERENCES dbo.Dim_Unit(unit_serial),

    CONSTRAINT FK_Fact_TestRun_Station
        FOREIGN KEY (station_id) REFERENCES dbo.Dim_Station(station_id)
);
GO

CREATE TABLE dbo.Fact_FieldReturn (
    rma_id               BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    unit_serial          VARCHAR(64)          NOT NULL,
    return_date          DATE                 NOT NULL,
    symptom_code         VARCHAR(64)          NOT NULL,  -- what field observed
    confirmed_failure_mode VARCHAR(64)        NULL,      -- after analysis/repair
    repair_action        VARCHAR(32)          NOT NULL,  -- REWORK/REPLACE/NFF
    notes               VARCHAR(256)          NULL,
    created_utc          DATETIME2(0)         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_Fact_FieldReturn_Unit
        FOREIGN KEY (unit_serial) REFERENCES dbo.Dim_Unit(unit_serial)
);
GO

-- Optional time-series-ish telemetry for burn-in (for early anomaly detection)
CREATE TABLE dbo.Fact_BurnInTelemetry (
    telemetry_id         BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    unit_serial          VARCHAR(64)          NOT NULL,
    ts                   DATETIME2(0)         NOT NULL,
    temp_c               FLOAT                NULL,
    vcore_v              FLOAT                NULL,
    ripple_mv            FLOAT                NULL,
    ber_snapshot         FLOAT                NULL,
    created_utc          DATETIME2(0)         NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_Fact_BurnInTelemetry_Unit
        FOREIGN KEY (unit_serial) REFERENCES dbo.Dim_Unit(unit_serial)
);
GO

/* -------------------- Indexes (big-impact for interview demos) -------------------- */

-- Fact_TestRun: common filters are time + pass_fail + failure_code + unit_serial + station_id
CREATE INDEX IX_Fact_TestRun_UnitSerial_StartTs
ON dbo.Fact_TestRun (unit_serial, start_ts);

CREATE INDEX IX_Fact_TestRun_Station_StartTs
ON dbo.Fact_TestRun (station_id, start_ts);

CREATE INDEX IX_Fact_TestRun_PassFail_FailureCode
ON dbo.Fact_TestRun (pass_fail, failure_code)
INCLUDE (test_type, start_ts, unit_serial);

-- Dim_Unit: useful for joining build_date, lot, linecard quickly
CREATE INDEX IX_Dim_Unit_LineCard_Lot_BuildDate
ON dbo.Dim_Unit (linecard_id, supplier_lot_id, build_date);

-- Field returns: time-to-failure and NFF analysis
CREATE INDEX IX_Fact_FieldReturn_UnitSerial_ReturnDate
ON dbo.Fact_FieldReturn (unit_serial, return_date);

CREATE INDEX IX_Fact_FieldReturn_RepairAction
ON dbo.Fact_FieldReturn (repair_action)
INCLUDE (return_date, symptom_code, confirmed_failure_mode, unit_serial);

-- Burn-in telemetry: time series per unit
CREATE INDEX IX_Fact_BurnInTelemetry_UnitSerial_Ts
ON dbo.Fact_BurnInTelemetry (unit_serial, ts);
GO

