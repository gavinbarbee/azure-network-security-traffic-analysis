output "spoke1_private_ip" {
  value = azurerm_network_interface.spoke1.private_ip_address
}

output "spoke2_private_ip" {
  value = azurerm_network_interface.spoke2.private_ip_address
}

output "firewall_private_ip" {
  value = azurerm_firewall.main.ip_configuration[0].private_ip_address
}
