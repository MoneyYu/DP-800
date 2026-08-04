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
    reset-adventuregear.sql
    統一示範已核准的完整（資料庫層級）重設資產。這是唯一允許卸除資料庫的重設指令碼，且它被硬性限定為單一字面 AdventureGearAI 資料庫。它不含動態 SQL：每個破壞性陳述式都以字面 [AdventureGearAI] 指定目標，因此目標永遠無法被重新導向。
    流程（安全且具決定性）：1. 從 master 控制。2. 若 AdventureGearAI 存在，強制設為 SINGLE_USER WITH ROLLBACK IMMEDIATE，讓任何開啟的工作階段都會回復並中斷連線。3. 卸除 AdventureGearAI 資料庫。
    Reset-AdventureGearAI.ps1 包裝函式會針對 master 叫用此資產，接著重新執行核心 bootstrap，留下剛完成 bootstrap 的 AdventureGearAI。絕不參考或變更舊版 DP800_Mxx 資料庫。
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
