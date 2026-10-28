/*
=============================================================
Script  : 02_ddl_audit.sql
Purpose : Creates audit.load_log, which records every load
          (table, start/end time, duration, rows, status, error).
=============================================================
*/

USE OlistDWH;
GO

IF OBJECT_ID('audit.load_log', 'U') IS NOT NULL
    DROP TABLE audit.load_log;
GO

CREATE TABLE audit.load_log (
    log_id            INT IDENTITY(1,1) PRIMARY KEY,
    layer             NVARCHAR(20)   NOT NULL,
    table_name        NVARCHAR(100)  NOT NULL,
    load_start        DATETIME2      NOT NULL,
    load_end          DATETIME2      NULL,
    duration_seconds  INT            NULL,
    rows_loaded       INT            NULL,
    status            NVARCHAR(20)   NOT NULL,   -- SUCCESS / FAILED
    error_message     NVARCHAR(4000) NULL
);
GO

