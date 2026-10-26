/*
=============================================================
Script   : 01_create_database.sql
Purpose  : Creates the OlistDWH database and the four schemas
           (bronze, silver, gold, audit).
WARNING  : If OlistDWH already exists it is DROPPED and
           recreated. Run only in a development environment.
=============================================================
*/

USE master;
GO

-- Drop and recreate the database if it already exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'OlistDWH')
BEGIN
    ALTER DATABASE OlistDWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OlistDWH;
END;
GO

CREATE DATABASE OlistDWH;
GO

USE OlistDWH;
GO

-- One schema per layer, plus audit for logging
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO
CREATE SCHEMA audit;
GO