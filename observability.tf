# =============================================================
# observability.tf — Sab Devyani-RG mein
# POINT 12:
#   - Managed Identity (per spoke)
#   - Key Vault (per spoke)
#   - Log Analytics Workspace
#   - Application Insights (per spoke)
#   - Diagnostic Settings (Firewall, AppGW, App Services, PostgreSQL)
# =============================================================

data "azurerm_client_config" "current" {}

# =============================================================
# MANAGED IDENTITY — per spoke (dev + prod)
# =============================================================
resource "azurerm_user_assigned_identity" "spokes" {
  for_each            = var.spoke_configs
  name                = "${each.key}-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.devyani.name
  tags                = merge(var.common_tags, { environment = each.key })
}

# =============================================================
# LOG ANALYTICS WORKSPACE — central, single workspace
# =============================================================
resource "azurerm_log_analytics_workspace" "hub" {
  name                = "devyani-log-analytics"
  location            = var.location
  resource_group_name = azurerm_resource_group.devyani.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = merge(var.common_tags, { service = "log-analytics" })
}

# =============================================================
# APPLICATION INSIGHTS — per spoke
# =============================================================
resource "azurerm_application_insights" "spokes" {
  for_each            = var.spoke_configs
  name                = "${each.key}-appinsights"
  location            = var.location
  resource_group_name = azurerm_resource_group.devyani.name
  workspace_id        = azurerm_log_analytics_workspace.hub.id
  application_type    = "web"
  tags                = merge(var.common_tags, { environment = each.key })
}

# =============================================================
# KEY VAULT — per spoke
# =============================================================
resource "azurerm_key_vault" "spokes" {
  for_each                   = var.spoke_configs
  name                       = "${each.key}-kv-devyani"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.devyani.name
  sku_name                   = var.key_vault_sku
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = each.key == "prod" ? true : false

  # Managed Identity ko Key Vault access
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.spokes[each.key].principal_id

    secret_permissions      = ["Get", "List"]
    certificate_permissions = ["Get", "List"]
    key_permissions         = ["Get", "List"]
  }

  # Terraform deployer ko full access (deployment ke liye)
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
    ]
    certificate_permissions = [
      "Get", "List", "Create", "Delete", "Import", "Update", "Recover", "Purge"
    ]
    key_permissions = [
      "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
    ]
  }

  network_acls {
    default_action = "Allow" # prod mein "Deny" kar sakte ho private endpoint ke baad
    bypass         = "AzureServices"
  }

  tags = merge(var.common_tags, { environment = each.key })
}

# PostgreSQL password Key Vault mein store karo
resource "azurerm_key_vault_secret" "postgres_password" {
  for_each     = var.spoke_configs
  name         = "postgres-admin-password"
  value        = var.postgres_admin_password
  key_vault_id = azurerm_key_vault.spokes[each.key].id
  tags         = merge(var.common_tags, { environment = each.key })
  depends_on   = [azurerm_key_vault.spokes]
}

# =============================================================
# DIAGNOSTIC SETTINGS
# =============================================================

# --- Azure Firewall ---
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "firewall-diag"
  target_resource_id         = azurerm_firewall.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log { category = "AzureFirewallApplicationRule" }
  enabled_log { category = "AzureFirewallNetworkRule" }
  enabled_log { category = "AzureFirewallDnsProxy" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- Application Gateway ---
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "appgw-diag"
  target_resource_id         = azurerm_application_gateway.hub.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- App Services (all 4) ---
resource "azurerm_monitor_diagnostic_setting" "app_services" {
  for_each                   = local.app_service_combos
  name                       = "${each.key}-diag"
  target_resource_id         = azurerm_linux_web_app.spokes[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_log { category = "AppServiceAuditLogs" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- PostgreSQL (Dev + Prod) ---
resource "azurerm_monitor_diagnostic_setting" "postgres" {
  for_each                   = var.spoke_configs
  name                       = "${each.key}-postgres-diag"
  target_resource_id         = azurerm_postgresql_flexible_server.spokes[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log { category = "PostgreSQLLogs" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- Key Vaults ---
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  for_each                   = var.spoke_configs
  name                       = "${each.key}-kv-diag"
  target_resource_id         = azurerm_key_vault.spokes[each.key].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id

  enabled_log { category = "AuditEvent" }
  enabled_log { category = "AzurePolicyEvaluationDetails" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
