/*
    report-legacy-databases.sql

    Reports any pre-existing per-module databases (the retired DP800_Mxx fleet)
    as MANUAL cleanup candidates only. This script never creates, alters, or
    drops any database; the unified demo owns only AdventureGearAI. Operators
    decide whether to remove the legacy databases manually.
*/
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name LIKE N'DP800[_]M[0-9][0-9]')
BEGIN
    PRINT N'Legacy per-module databases detected. These are MANUAL cleanup candidates only and are never dropped automatically:';
    SELECT name AS LegacyCleanupCandidate
    FROM sys.databases
    WHERE name LIKE N'DP800[_]M[0-9][0-9]'
    ORDER BY name;
END
ELSE
BEGIN
    PRINT N'No legacy per-module databases detected.';
END;
GO
