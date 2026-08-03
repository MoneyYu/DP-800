SET NOCOUNT ON;
GO

DECLARE @ModuleNumber int = 1;
DECLARE @DatabaseName sysname;
DECLARE @Sql nvarchar(max);

WHILE @ModuleNumber <= 11
BEGIN
    SET @DatabaseName = CONCAT(N'DP800_M', RIGHT(CONCAT(N'0', @ModuleNumber), 2));

    IF DB_ID(@DatabaseName) IS NULL
    BEGIN
        SET @Sql = N'CREATE DATABASE ' + QUOTENAME(@DatabaseName) + N';';
        EXEC sys.sp_executesql @Sql;
        PRINT CONCAT(N'Created ', @DatabaseName);
    END
    ELSE
        PRINT CONCAT(@DatabaseName, N' already exists; skipped.');

    SET @ModuleNumber += 1;
END;
GO

