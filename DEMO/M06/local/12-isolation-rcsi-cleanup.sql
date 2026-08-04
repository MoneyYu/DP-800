/* Removes only the temporary M06 isolation probe database. */
USE master;
GO

IF DB_ID(N'DP800_M06_IsolationProbe') IS NOT NULL
BEGIN
    ALTER DATABASE [DP800_M06_IsolationProbe] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [DP800_M06_IsolationProbe];
END;
GO
