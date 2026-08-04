# Azure notes

Run this module's setup against an Azure SQL database that hosts the
AdventureGearAI schema set. Temporal tables, indexed computed JSON columns,
range partitioning, and SQL graph node/edge tables are all available on Azure
SQL, but Azure SQL manages storage rather than exposing the same filegroup
design choices as boxed SQL Server, so `PS_AdventureGear_OrderDate` maps to the
primary filegroup. Verify the service objective, ledger requirements, and any
preview status in the target database before teaching them.
