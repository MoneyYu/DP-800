# Azure notes

The sales programmability objects use portable Azure SQL syntax and run against
the AdventureGearAI schema set on Azure SQL. For production, replace broad
execution rights with least-privilege grants, use Entra principals where
required, and test trigger/procedure concurrency under the Azure service tier
selected for the application.
