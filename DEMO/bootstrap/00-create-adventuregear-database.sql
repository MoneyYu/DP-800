/*
    00-create-adventuregear-database.sql

    Idempotently creates the single unified demo database, literally named
    AdventureGearAI, from the master database. This is the only database the
    unified demo ever creates. Retired per-module databases are never created,
    altered, or dropped here; they are reported elsewhere as manual cleanup
    candidates only.
*/
SET NOCOUNT ON;
GO

USE master;
GO

IF DB_ID(N'AdventureGearAI') IS NULL
BEGIN
    PRINT N'Creating AdventureGearAI database.';
    CREATE DATABASE [AdventureGearAI];
END
ELSE
BEGIN
    PRINT N'AdventureGearAI already exists; skipping create.';
END;
GO
