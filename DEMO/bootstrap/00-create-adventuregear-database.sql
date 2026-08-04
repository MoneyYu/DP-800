/*
    00-create-adventuregear-database.sql

    Idempotently creates the single unified demo database, literally named
    AdventureGearAI, from the master database. This is the only database the
    unified demo ever creates. Retired per-module databases are never created,
    altered, or dropped here; they are reported elsewhere as manual cleanup
    candidates only.
    00-create-adventuregear-database.sql
    從 master 資料庫以冪等方式建立名為 AdventureGearAI 的單一統一示範資料庫。這是統一示範唯一會建立的資料庫。已淘汰的每模組資料庫絕不會在此建立、變更或卸除；它們只會在其他位置被報告為手動清理候選項。
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
