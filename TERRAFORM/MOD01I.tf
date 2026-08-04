## MOD-01-I-AUTOMATION

resource "azurerm_automation_account" "lab01i" {
  count = var.enable_operations ? 1 : 0

  name                = "${local.lab01_name}-automation-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = local.default_tags
}

resource "azurerm_automation_credential" "lab01i_sqladmin" {
  count = var.enable_operations && var.enable_azure_sql_gallery && var.enable_azure_services_firewall_demo ? 1 : 0

  name                    = "sql-maint-admin"
  resource_group_name     = azurerm_resource_group.dp300.name
  automation_account_name = azurerm_automation_account.lab01i[0].name
  username                = local.effective_admin_username
  password                = local.effective_admin_password
  description             = "SQL admin credential for scheduled maintenance runbook."
}

# Runbook keeps Azure SQL DB statistics refreshed and validates integrity.
resource "azurerm_automation_runbook" "lab01i_sql_maintenance" {
  count = var.enable_operations && var.enable_azure_sql_gallery && var.enable_azure_services_firewall_demo ? 1 : 0

  name                    = "sql-maintenance"
  resource_group_name     = azurerm_resource_group.dp300.name
  automation_account_name = azurerm_automation_account.lab01i[0].name
  location                = azurerm_resource_group.dp300.location
  log_progress            = true
  log_verbose             = true
  runbook_type            = "PowerShell"
  # The scheduled SqlPassword path uses Get-AutomationPSCredential, which Azure
  # provides only in the system-generated PowerShell 5.1 Runtime Environment.
  runtime_environment_name = "PowerShell-5.1"
  description              = "Executes Azure SQL Database maintenance (stats refresh + DBCC)."

  content = <<-POWERSHELL
    param (
      [Parameter(Mandatory = $true)]
      [string] $serverfqdn,
      [Parameter(Mandatory = $true)]
      [string] $databasename,
      [Parameter(Mandatory = $true)]
      [string] $credentialname,
      [Parameter(Mandatory = $true)]
      [ValidateSet("SqlPassword", "ManagedIdentity")]
      [string] $authenticationmode
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection

    if ($authenticationmode -eq "ManagedIdentity") {
      # Requires a contained external database user for the Automation account
      # system-assigned identity before this path is selected.
      Disable-AzContextAutosave -Scope Process | Out-Null
      Connect-AzAccount -Identity | Out-Null
      $token = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
      if ($token -is [System.Security.SecureString]) {
        $token = [System.Net.NetworkCredential]::new("", $token).Password
      }
      $connection.ConnectionString = "Server=tcp:$serverfqdn,1433;Database=$databasename;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
      $connection.AccessToken = $token
    }
    else {
      $cred = Get-AutomationPSCredential -Name $credentialname
      if (-not $cred) {
        throw "Credential $credentialname not found."
      }

      $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
      $builder["Data Source"] = "tcp:$serverfqdn,1433"
      $builder["Initial Catalog"] = $databasename
      $builder["User ID"] = $cred.UserName
      $builder["Password"] = $cred.GetNetworkCredential().Password
      $builder["Encrypt"] = $true
      $builder["TrustServerCertificate"] = $false
      $builder["Connect Timeout"] = 30
      $connection.ConnectionString = $builder.ConnectionString
    }

    $queries = @(
      "SET NOCOUNT ON; EXEC sp_updatestats;",
      "SET NOCOUNT ON; DBCC CHECKDB WITH NO_INFOMSGS;"
    )

    $command = $connection.CreateCommand()

    try {
      $connection.Open()
      foreach ($query in $queries) {
        $command.CommandText = $query
        $command.ExecuteNonQuery() | Out-Null
      }
      Write-Output "Maintenance completed for $databasename on $(Get-Date -Format o)"
    }
    catch {
      Write-Error "Maintenance failed: $($_.Exception.Message)"
      throw
    }
    finally {
      $connection.Close()
    }
  POWERSHELL

  tags = local.default_tags
}

resource "azurerm_automation_schedule" "lab01i_daily" {
  count = var.enable_operations && var.enable_azure_sql_gallery && var.enable_azure_services_firewall_demo ? 1 : 0

  name                    = "sql-maintenance-daily"
  resource_group_name     = azurerm_resource_group.dp300.name
  automation_account_name = azurerm_automation_account.lab01i[0].name
  frequency               = "Day"
  interval                = 1
  timezone                = "Asia/Taipei"
  description             = "Daily Azure SQL maintenance window."
}

resource "azurerm_automation_job_schedule" "lab01i_sql_maintenance" {
  count = var.enable_operations && var.enable_azure_sql_gallery && var.enable_azure_services_firewall_demo ? 1 : 0

  resource_group_name     = azurerm_resource_group.dp300.name
  automation_account_name = azurerm_automation_account.lab01i[0].name
  schedule_name           = azurerm_automation_schedule.lab01i_daily[0].name
  runbook_name            = azurerm_automation_runbook.lab01i_sql_maintenance[0].name

  parameters = {
    serverfqdn         = azurerm_mssql_server.lab01[0].fully_qualified_domain_name
    databasename       = azurerm_mssql_database.lab01d02[0].name
    credentialname     = azurerm_automation_credential.lab01i_sqladmin[0].name
    authenticationmode = "SqlPassword"
  }
}
