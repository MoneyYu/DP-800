## MOD-01-B-SQL-MI
resource "azurerm_network_security_group" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                = "${local.lab01b_name}-nsg-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name

  tags = local.default_tags
}


resource "azurerm_network_security_rule" "allow_mssql_inbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_public_tds_inbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3342"
  source_address_prefix       = local.effective_allowed_client_ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "allow_misubnet_inbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_misubnet_inbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "10.2.1.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "allow_health_probe_inbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_health_probe_inbound"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "allow_tds_inbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_tds_inbound"
  priority                    = 1000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "deny_all_inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "allow_management_outbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_management_outbound"
  priority                    = 102
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443", "12000"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "allow_misubnet_outbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "allow_misubnet_outbound"
  priority                    = 200
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "10.2.1.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_network_security_rule" "deny_all_outbound" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                        = "deny_all_outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01b[0].name
}

resource "azurerm_virtual_network" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                = "${local.lab01b_name}-vnet-${local.random_str}"
  resource_group_name = azurerm_resource_group.dp300.name
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.dp300.location

  tags = local.default_tags
}

resource "azurerm_subnet" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                 = "subnet-mi"
  resource_group_name  = azurerm_resource_group.dp300.name
  virtual_network_name = azurerm_virtual_network.lab01b[0].name
  address_prefixes     = ["10.2.1.0/24"]

  delegation {
    name = "managedinstancedelegation"

    service_delegation {
      name    = "Microsoft.Sql/managedInstances"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  subnet_id                 = azurerm_subnet.lab01b[0].id
  network_security_group_id = azurerm_network_security_group.lab01b[0].id
}

resource "azurerm_route_table" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                          = "${local.lab01b_name}-route-${local.random_str}"
  location                      = azurerm_resource_group.dp300.location
  resource_group_name           = azurerm_resource_group.dp300.name
  bgp_route_propagation_enabled = true
  depends_on = [
    azurerm_subnet.lab01b[0],
  ]

  tags = local.default_tags
}

resource "azurerm_subnet_route_table_association" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  subnet_id      = azurerm_subnet.lab01b[0].id
  route_table_id = azurerm_route_table.lab01b[0].id
}

resource "azurerm_mssql_managed_instance" "lab01b" {
  count = var.enable_sql_managed_instance ? 1 : 0

  name                = "${local.lab01b_name}-${var.group_postfix}-mssql-mi-${local.random_str}"
  resource_group_name = azurerm_resource_group.dp300.name
  location            = azurerm_resource_group.dp300.location

  license_type       = "BasePrice"
  sku_name           = "GP_Gen5"
  storage_size_in_gb = 32
  subnet_id          = azurerm_subnet.lab01b[0].id
  vcores             = 4
  collation          = "SQL_Latin1_General_CP1_CI_AS"

  administrator_login          = local.effective_admin_username
  administrator_login_password = local.effective_admin_password

  public_data_endpoint_enabled = true
  minimum_tls_version          = "1.2"

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.lab01b[0],
    azurerm_subnet_route_table_association.lab01b[0],
  ]

  tags = local.default_tags
}