/*
    reset-adventuregear.sql

    Approved full (database-level) reset asset for the unified demo. This is the
    ONLY reset script permitted to drop a database, and it is hard-scoped to the
    single literal AdventureGearAI database. It contains no dynamic SQL: every
    destructive statement names [AdventureGearAI] literally so the target can
    never be redirected.

    Flow (safe and deterministic):
      1. Control from master.
      2. If AdventureGearAI exists, force it to SINGLE_USER WITH ROLLBACK
         IMMEDIATE so any open sessions are rolled back and disconnected.
      3. DROP the AdventureGearAI database.

    The Reset-AdventureGearAI.ps1 wrapper invokes this asset against master and
    then re-runs the core bootstrap, leaving a freshly bootstrapped core
    AdventureGearAI. Legacy DP800_Mxx databases are never referenced or touched.
*/
USE master;
GO

IF DB_ID(N'AdventureGearAI') IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureGearAI] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureGearAI];
    PRINT N'AdventureGearAI dropped after rolling back active sessions.';
END
ELSE
BEGIN
    PRINT N'AdventureGearAI did not exist; nothing to drop.';
END;
GO
