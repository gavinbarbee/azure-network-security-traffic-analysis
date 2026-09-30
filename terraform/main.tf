terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ── Resource Group ──────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-lab-network-${var.yourname}"
  location = var.location
  tags     = var.tags
}

# ── Log Analytics Workspace ──────────────────────────────────
# Receives firewall logs and Traffic Analytics output from the VNet flow logs
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-lab-network-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ── Hub VNet and Subnets ─────────────────────────────────────
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

# Azure Firewall requires this exact subnet name
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Firewall Basic requires a management subnet with this exact name (/26 minimum)
resource "azurerm_subnet" "firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.3.0/26"]
}

# ── Spoke VNets ──────────────────────────────────────────────
resource "azurerm_virtual_network" "spoke1" {
  name                = "vnet-spoke1-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.1.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke1" {
  name                 = "spoke1-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke1.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_virtual_network" "spoke2" {
  name                = "vnet-spoke2-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.2.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke2" {
  name                 = "spoke2-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke2.name
  address_prefixes     = ["10.2.1.0/24"]
}

# ── VNet Peerings ────────────────────────────────────────────
# Peering connects VNets so they can communicate.
# Both directions must be created — Azure requires explicit bidirectional peering.
resource "azurerm_virtual_network_peering" "hub_to_spoke1" {
  name                      = "hub-to-spoke1"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke1.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "spoke1_to_hub" {
  name                      = "spoke1-to-hub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.spoke1.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_spoke2" {
  name                      = "hub-to-spoke2"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke2.id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "spoke2_to_hub" {
  name                      = "spoke2-to-hub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.spoke2.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true
}

# ── Azure Firewall ────────────────────────────────────────────
resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Management public IP required by the Basic SKU's management NIC
resource "azurerm_public_ip" "firewall_mgmt" {
  name                = "pip-firewall-mgmt-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Basic SKU firewalls are managed through a Firewall Policy (no classic rules)
resource "azurerm_firewall_policy" "main" {
  name                = "fwpol-lab-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Basic"
  tags                = var.tags
}

resource "azurerm_firewall" "main" {
  name                = "fw-lab-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic" # Basic is the lowest cost option
  firewall_policy_id  = azurerm_firewall_policy.main.id

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  management_ip_configuration {
    name                 = "fw-mgmt-ipconfig"
    subnet_id            = azurerm_subnet.firewall_mgmt.id
    public_ip_address_id = azurerm_public_ip.firewall_mgmt.id
  }

  tags = var.tags
}

# Send firewall logs to Log Analytics in resource-specific (structured) tables
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-firewall"
  target_resource_id             = azurerm_firewall.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Allow ICMP and TCP between spokes through the firewall
resource "azurerm_firewall_policy_rule_collection_group" "spoke_to_spoke" {
  name               = "rcg-spoke-to-spoke"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100

  network_rule_collection {
    name     = "allow-spoke-to-spoke"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-icmp-tcp"
      protocols             = ["ICMP", "TCP"]
      source_addresses      = ["10.1.0.0/16", "10.2.0.0/16"]
      destination_addresses = ["10.1.0.0/16", "10.2.0.0/16"]
      destination_ports     = ["*"]
    }
  }
}

# ── UDRs — force spoke traffic through the firewall ──────────
# Without these, Azure routes traffic directly between peered VNets.
# The UDR overrides that default and sends traffic to the firewall IP.
resource "azurerm_route_table" "spoke1" {
  name                = "rt-spoke1-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "to-spoke2-via-fw"
    address_prefix         = "10.2.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }

  tags = var.tags
}

resource "azurerm_subnet_route_table_association" "spoke1" {
  subnet_id      = azurerm_subnet.spoke1.id
  route_table_id = azurerm_route_table.spoke1.id
}

resource "azurerm_route_table" "spoke2" {
  name                = "rt-spoke2-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "to-spoke1-via-fw"
    address_prefix         = "10.1.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }

  tags = var.tags
}

resource "azurerm_subnet_route_table_association" "spoke2" {
  subnet_id      = azurerm_subnet.spoke2.id
  route_table_id = azurerm_route_table.spoke2.id
}

# ── NSG for the spoke VM NICs ────────────────────────────────
resource "azurerm_network_security_group" "spoke" {
  name                = "nsg-spokes-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-icmp"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# ── VNet Flow Logs + Traffic Analytics ───────────────────────
resource "azurerm_storage_account" "flowlogs" {
  name                     = "stflowlogs${var.yourname}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

# Network Watcher is platform-owned: Azure auto-creates one per region per
# subscription (NetworkWatcher_<region> in NetworkWatcherRG) when a VNet is
# created. Wait for it, then reference it instead of creating a second one.
resource "time_sleep" "wait_for_network_watcher" {
  create_duration = "60s"

  depends_on = [
    azurerm_virtual_network.hub,
    azurerm_virtual_network.spoke1,
    azurerm_virtual_network.spoke2,
  ]
}

data "azurerm_network_watcher" "main" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"

  depends_on = [time_sleep.wait_for_network_watcher]
}

resource "azurerm_network_watcher_flow_log" "spoke1" {
  network_watcher_name = data.azurerm_network_watcher.main.name
  resource_group_name  = data.azurerm_network_watcher.main.resource_group_name
  name                 = "flowlog-spoke1-${var.yourname}"
  target_resource_id   = azurerm_virtual_network.spoke1.id
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

resource "azurerm_network_watcher_flow_log" "spoke2" {
  network_watcher_name = data.azurerm_network_watcher.main.name
  resource_group_name  = data.azurerm_network_watcher.main.resource_group_name
  name                 = "flowlog-spoke2-${var.yourname}"
  target_resource_id   = azurerm_virtual_network.spoke2.id
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

# ── Two Ubuntu VMs (size chosen from the pre-flight check) ───
resource "azurerm_network_interface" "spoke1" {
  name                = "nic-spoke1-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke1.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "spoke1" {
  network_interface_id      = azurerm_network_interface.spoke1.id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

resource "azurerm_linux_virtual_machine" "spoke1" {
  name                            = "vm-spoke1-${var.yourname}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.spoke1.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}

# Packet capture runs through the Network Watcher agent extension on the VM
resource "azurerm_virtual_machine_extension" "nw_agent_spoke1" {
  name                       = "AzureNetworkWatcherExtension"
  virtual_machine_id         = azurerm_linux_virtual_machine.spoke1.id
  publisher                  = "Microsoft.Azure.NetworkWatcher"
  type                       = "NetworkWatcherAgentLinux"
  type_handler_version       = "1.4"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

resource "azurerm_network_interface" "spoke2" {
  name                = "nic-spoke2-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "spoke2" {
  network_interface_id      = azurerm_network_interface.spoke2.id
  network_security_group_id = azurerm_network_security_group.spoke.id
}

resource "azurerm_linux_virtual_machine" "spoke2" {
  name                            = "vm-spoke2-${var.yourname}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.spoke2.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}
