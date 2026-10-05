# =============================================================
# spoke_paas.tf
# Existing: NSGs (frontend/backend/database) in rg-dev / rg-prod
# New (Devyani-RG): App Service Plans, App Services,
#                   PostgreSQL, Private DNS, Managed Identity
# =============================================================

# =============================================================
# NSGs — existing, state se match
# frontend, backend, database — rg-dev / rg-prod mein hain
# =============================================================
resource "azurerm_network_security_group" "frontend" {
  for_each            = var.spoke_configs
  name                = "${each.key}-frontend-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.spokes[each.key].name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(var.common_tags, { environment = each.key, tier = "frontend" })
}

resource "azurerm_network_security_group" "backend" {
  for_each            = var.spoke_configs
  name                = "${each.key}-backend-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.spokes[each.key].name

  security_rule {
    name                       = "allow-internal"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-internet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = merge(var.common_tags, { environment = each.key, tier = "backend" })
}

resource "azurerm_network_security_group" "database" {
  for_each            = var.spoke_configs
  name                = "${each.key}-database-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.spokes[each.key].name

  security_rule {
    name                       = "allow-postgres"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.0.0.0/8"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge(var.common_tags, { environment = each.key, tier = "database" })
}

# NSG Associations — existing (frontend, backend, database subnets)
locals {
  nsg_associations = merge(
    { for k, v in var.spoke_configs : "${k}/frontend" => {
      subnet_key = "${k}/frontend"
      nsg_id     = azurerm_network_security_group.frontend[k].id
    } },
    { for k, v in var.spoke_configs : "${k}/backend" => {
      subnet_key = "${k}/backend"
      nsg_id     = azurerm_network_security_group.backend[k].id
    } },
    { for k, v in var.spoke_configs : "${k}/database" => {
      subnet_key = "${k}/database"
      nsg_id     = azurerm_network_security_group.database[k].id
    } }
  )
}

resource "azurerm_subnet_network_security_group_association" "spokes" {
  for_each                  = local.nsg_associations
  subnet_id                 = azurerm_subnet.spokes[each.value.subnet_key].id
  network_security_group_id = each.value.nsg_id
  depends_on = [
    azurerm_subnet.spokes,
    azurerm_network_security_group.frontend,
    azurerm_network_security_group.backend,
    azurerm_network_security_group.database,
  ]
}

# =============================================================
# NEW RESOURCES — Devyani-RG mein
# =============================================================

# APP SERVICE PLANS
resource "azurerm_service_plan" "spokes" {
  for_each            = var.spoke_configs
  name                = "${each.key}-asp"
  location            = var.location
  resource_group_name = azurerm_resource_group.devyani.name
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku[each.key]
  tags                = merge(var.common_tags, { environment = each.key })
  depends_on          = [azurerm_resource_group.devyani]
}

# APP SERVICES — dev-frontend, dev-backend, prod-frontend, prod-backend
resource "azurerm_linux_web_app" "spokes" {
  for_each            = local.app_service_combos
  name                = each.value.name
  location            = var.location
  resource_group_name = azurerm_resource_group.devyani.name
  service_plan_id     = azurerm_service_plan.spokes[each.value.spoke_key].id

  # VNet Integration — appservice subnet (delegated)
  virtual_network_subnet_id     = azurerm_subnet.spokes["${each.value.spoke_key}/appservice"].id
  public_network_access_enabled = true
  https_only                    = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.spokes[each.value.spoke_key].id]
  }

  site_config {
    always_on           = each.value.spoke_key == "prod" ? true : false
    http2_enabled       = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    health_check_path   = "/health"

    application_stack {
      node_version   = can(regex("^NODE", each.value.runtime)) ? split("|", each.value.runtime)[1] : null
      python_version = can(regex("^PYTHON", each.value.runtime)) ? split("|", each.value.runtime)[1] : null
    }
  }

  app_settings = {
    ENVIRONMENT                                = upper(each.value.spoke_key)
    APP_TIER                                   = upper(each.value.tier)
    AZURE_CLIENT_ID                            = azurerm_user_assigned_identity.spokes[each.value.spoke_key].client_id
    KEY_VAULT_URI                              = azurerm_key_vault.spokes[each.value.spoke_key].vault_uri
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.spokes[each.value.spoke_key].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    DATABASE_URL                               = each.value.tier == "backend" ? "postgresql://${var.postgres_admin_user}@${azurerm_postgresql_flexible_server.spokes[each.value.spoke_key].fqdn}:5432/${var.postgres_config[each.value.spoke_key].db_name}?sslmode=require" : null
    BACKEND_URL                                = each.value.tier == "frontend" ? "https://${each.value.spoke_key}-backend-app.azurewebsites.net" : null
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = each.value.spoke_key == "prod" ? 30 : 7
        retention_in_mb   = 35
      }
    }
  }

  tags = merge(var.common_tags, { environment = each.value.spoke_key, tier = each.value.tier })

  depends_on = [
    azurerm_service_plan.spokes,
    azurerm_subnet.spokes,
    azurerm_user_assigned_identity.spokes,
    azurerm_application_insights.spokes,
    azurerm_key_vault.spokes,
    azurerm_postgresql_flexible_server.spokes,
  ]
}

# =============================================================
# PRIVATE DNS ZONE — PostgreSQL (Devyani-RG)
# =============================================================
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.devyani.name
  tags                = var.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_spokes" {
  for_each              = var.spoke_configs
  name                  = "postgres-link-${each.key}"
  resource_group_name   = azurerm_resource_group.devyani.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.spokes[each.key].id
  registration_enabled  = false
  tags                  = merge(var.common_tags, { environment = each.key })
  depends_on            = [azurerm_virtual_network.spokes]
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_hub" {
  name                  = "postgres-link-hub"
  resource_group_name   = azurerm_resource_group.devyani.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = var.common_tags
  depends_on            = [azurerm_virtual_network.hub]
}

# =============================================================
# POSTGRESQL FLEXIBLE SERVER — Dev + Prod (Devyani-RG)
# =============================================================
resource "azurerm_postgresql_flexible_server" "spokes" {
  for_each               = var.spoke_configs
  name                   = "${each.key}-postgres-server"
  location               = var.location
  resource_group_name    = azurerm_resource_group.devyani.name
  version                = var.postgres_config[each.key].pg_version
  administrator_login    = var.postgres_admin_user
  administrator_password = var.postgres_admin_password
  sku_name               = var.postgres_config[each.key].sku_name
  storage_mb             = var.postgres_config[each.key].storage_mb
  zone                   = "1"

  delegated_subnet_id = azurerm_subnet.spokes["${each.key}/database"].id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  backup_retention_days        = var.postgres_config[each.key].backup_retention_days
  geo_redundant_backup_enabled = var.postgres_config[each.key].geo_redundant_backup

  dynamic "high_availability" {
    for_each = var.postgres_config[each.key].high_availability ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  tags = merge(var.common_tags, { environment = each.key, tier = "database" })

  depends_on = [
    azurerm_subnet.spokes,
    azurerm_private_dns_zone_virtual_network_link.postgres_spokes,
    azurerm_private_dns_zone_virtual_network_link.postgres_hub,
  ]
}

resource "azurerm_postgresql_flexible_server_database" "spokes" {
  for_each  = var.spoke_configs
  name      = var.postgres_config[each.key].db_name
  server_id = azurerm_postgresql_flexible_server.spokes[each.key].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_configuration" "ssl" {
  for_each  = var.spoke_configs
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.spokes[each.key].id
  value     = "on"
}
