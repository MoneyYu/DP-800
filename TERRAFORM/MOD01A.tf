## MOD-01-A-MSSQL-VM
resource "azurerm_virtual_network" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                = "${local.lab01a_name}-vnet-${local.random_str}"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name

  tags = local.default_tags
}

resource "azurerm_subnet" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                 = "default"
  resource_group_name  = azurerm_resource_group.dp300.name
  virtual_network_name = azurerm_virtual_network.lab01a[0].name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_public_ip" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                = "${local.lab01a_name}-${var.group_postfix}-pip-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name
  allocation_method   = "Static"
  domain_name_label   = "${local.lab01a_name}-${var.group_postfix}-pip-${local.random_str}"
  sku                 = "Standard"

  tags = local.default_tags
}

resource "azurerm_network_security_group" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                = "${local.lab01a_name}-nsg-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name

  tags = local.default_tags
}

resource "azurerm_network_security_rule" "lab01a01" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                        = "RDP"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = local.effective_allowed_client_ip
  destination_port_range      = "3389"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01a[0].name
}

resource "azurerm_network_security_rule" "lab01a02" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                        = "MSSQL"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  source_address_prefix       = local.effective_allowed_client_ip
  destination_port_range      = "1433"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.dp300.name
  network_security_group_name = azurerm_network_security_group.lab01a[0].name
}

resource "azurerm_network_interface" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                = "${local.lab01a_name}-nic-${local.random_str}"
  location            = azurerm_resource_group.dp300.location
  resource_group_name = azurerm_resource_group.dp300.name

  ip_configuration {
    name                          = "${local.lab01a_name}-nic-ipconfig-${local.random_str}"
    subnet_id                     = azurerm_subnet.lab01a[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab01a[0].id
  }

  tags = local.default_tags
}

resource "azurerm_network_interface_security_group_association" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  network_interface_id      = azurerm_network_interface.lab01a[0].id
  network_security_group_id = azurerm_network_security_group.lab01a[0].id
}

resource "azurerm_subnet_network_security_group_association" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  subnet_id                 = azurerm_subnet.lab01a[0].id
  network_security_group_id = azurerm_network_security_group.lab01a[0].id
}

resource "azurerm_windows_virtual_machine" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                  = "${local.lab01a_name}-sqlvm-${local.random_str}"
  location              = azurerm_resource_group.dp300.location
  resource_group_name   = azurerm_resource_group.dp300.name
  network_interface_ids = [azurerm_network_interface.lab01a[0].id]
  size                  = "Standard_B4ms"

  computer_name  = "${local.lab01a_name}-vm-${local.random_str}"
  admin_username = local.effective_admin_username
  admin_password = local.effective_admin_password

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2019-ws2019"
    sku       = "sqldev-gen2"
    version   = "latest"
  }

  provision_vm_agent        = true
  automatic_updates_enabled = true
  patch_assessment_mode     = "AutomaticByPlatform"
  patch_mode                = "AutomaticByPlatform"
  reboot_setting            = "IfRequired"
  timezone                  = "Taipei Standard Time"

  tags = local.default_tags
}

resource "azurerm_managed_disk" "lab01a_datadisk" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                 = "${local.lab01a_name}-datadisk-${local.random_str}"
  location             = azurerm_resource_group.dp300.location
  resource_group_name  = azurerm_resource_group.dp300.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 256

  tags = local.default_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "lab01a_datadisk_attach" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.lab01a_datadisk[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.lab01a[0].id
  lun                = 1
  caching            = "ReadWrite"
}

# add a log disk - we were going to iterate through a collection, but this is easier for now
resource "azurerm_managed_disk" "lab01a_logdisk" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  name                 = "${local.lab01a_name}-logdisk-${local.random_str}"
  location             = azurerm_resource_group.dp300.location
  resource_group_name  = azurerm_resource_group.dp300.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128

  tags = local.default_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "lab01a_logdisk_attach" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.lab01a_logdisk[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.lab01a[0].id
  lun                = 2
  caching            = "ReadWrite"
}

resource "azurerm_mssql_virtual_machine" "lab01a" {
  count = var.enable_sql_vm_2019 ? 1 : 0

  virtual_machine_id               = azurerm_windows_virtual_machine.lab01a[0].id
  sql_license_type                 = "PAYG"
  r_services_enabled               = true
  sql_connectivity_port            = 1433
  sql_connectivity_type            = "PUBLIC"
  sql_connectivity_update_username = local.effective_admin_username
  sql_connectivity_update_password = local.effective_admin_password

  auto_patching {
    day_of_week                            = "Sunday"
    maintenance_window_duration_in_minutes = 60
    maintenance_window_starting_hour       = 2
  }

  dynamic "auto_backup" {
    for_each = var.enable_legacy_key_auth_demo && var.enable_azure_sql_gallery ? [1] : []

    content {
      retention_period_in_days   = 7
      storage_blob_endpoint      = azurerm_storage_account.lab01[0].primary_blob_endpoint
      storage_account_access_key = azurerm_storage_account.lab01[0].primary_access_key
    }
  }

  assessment {
    enabled         = true
    run_immediately = true

    schedule {
      weekly_interval = 1
      day_of_week     = "Sunday"
      start_time      = "02:00"
    }
  }

  storage_configuration {
    disk_type             = "NEW"
    storage_workload_type = "OLTP"

    data_settings {
      default_file_path = "F:\\data"
      luns              = [azurerm_virtual_machine_data_disk_attachment.lab01a_datadisk_attach[0].lun]
    }

    log_settings {
      default_file_path = "G:\\log"
      luns              = [azurerm_virtual_machine_data_disk_attachment.lab01a_logdisk_attach[0].lun]
    }
  }

  tags = local.default_tags
}
