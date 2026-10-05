# =============================================================
# outputs.tf
# =============================================================

output "resource_group" {
  value = azurerm_resource_group.devyani.name
}

output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "spoke_vnet_ids" {
  value = { for k, v in azurerm_virtual_network.spokes : k => v.id }
}

output "firewall_private_ip" {
  value = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "app_service_urls" {
  value = { for k, v in azurerm_linux_web_app.spokes : k => "https://${v.default_hostname}" }
}

output "postgres_fqdns" {
  description = "PostgreSQL FQDNs — private only"
  value       = { for k, v in azurerm_postgresql_flexible_server.spokes : k => v.fqdn }
}

output "key_vault_uris" {
  value = { for k, v in azurerm_key_vault.spokes : k => v.vault_uri }
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.hub.id
}

output "app_insights_connection_strings" {
  sensitive = true
  value     = { for k, v in azurerm_application_insights.spokes : k => v.connection_string }
}

output "summary" {
  value = {
    resource_group = azurerm_resource_group.devyani.name
    hub = {
      vnet          = var.hub_config.name
      address_space = var.hub_config.address_space
      firewall_ip   = azurerm_firewall.hub.ip_configuration[0].private_ip_address
      appgw_pip     = azurerm_public_ip.appgw.ip_address
    }
    spokes = {
      for k, spoke in var.spoke_configs : k => {
        vnet          = spoke.name
        address_space = spoke.address_space
        frontend_url  = "https://${k}-frontend-app.azurewebsites.net"
        backend_url   = "https://${k}-backend-app.azurewebsites.net"
        postgres      = "${k}-postgres-server.postgres.database.azure.com"
        key_vault     = "${k}-kv-devyani.vault.azure.net"
      }
    }
  }
}
