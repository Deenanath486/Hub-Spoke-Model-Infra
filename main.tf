# =============================================================
# main.tf
# Existing resources — rg-hub, rg-dev, rg-prod mein hain
# Inhe touch nahi karna — state match karo
# New resources Devyani-RG mein jayenge (devyani_extra.tf mein)
# =============================================================

locals {
  hub_subnets_base = var.hub_config.subnets

  hub_gateway_subnet = var.enable_gateway_subnet ? {
    gateway = {
      name           = "GatewaySubnet"
      address_prefix = var.gateway_subnet_prefix
    }
  } : {}

  hub_subnets = merge(local.hub_subnets_base, local.hub_gateway_subnet)

  spoke_subnets = merge([
    for spoke_key, spoke in var.spoke_configs : {
      for snet_key, snet in spoke.subnets :
      "${spoke_key}/${snet_key}" => {
        spoke_key      = spoke_key
        snet_key       = snet_key
        name           = snet.name
        address_prefix = snet.address_prefix
      }
    }
  ]...)

  app_service_combos = merge([
    for spoke_key, spoke in var.spoke_configs : {
      for app_key, app in var.app_services :
      "${spoke_key}-${app_key}" => {
        spoke_key = spoke_key
        app_key   = app_key
        name      = "${spoke_key}-${app_key}-app"
        runtime   = app.runtime
        tier      = app.tier
      }
    }
  ]...)

  peering_spokes = var.spoke_configs
}

# =============================================================
# RESOURCE GROUPS — existing, state se match
# =============================================================
resource "azurerm_resource_group" "hub" {
  name     = var.hub_config.resource_group
  location = var.location
  tags     = merge(var.common_tags, { environment = "hub" })
}

resource "azurerm_resource_group" "spokes" {
  for_each = var.spoke_configs
  name     = each.value.resource_group
  location = var.location
  tags     = merge(var.common_tags, { environment = each.key })
}

# Devyani-RG — existing, import karo
# terraform import azurerm_resource_group.devyani /subscriptions/cc6eb6b0-ec2f-4e39-9a40-37a2b2ea1ba8/resourceGroups/Devyani-RG
resource "azurerm_resource_group" "devyani" {
  name     = var.resource_group_name
  location = var.location
  tags     = merge(var.common_tags, { note = "primary-existing-rg" })

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags]
  }
}

# =============================================================
# VIRTUAL NETWORKS — existing
# =============================================================
resource "azurerm_virtual_network" "hub" {
  name                = var.hub_config.name
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_config.address_space]
  tags                = merge(var.common_tags, { role = "hub" })
  depends_on          = [azurerm_resource_group.hub]
}

resource "azurerm_virtual_network" "spokes" {
  for_each            = var.spoke_configs
  name                = each.value.name
  location            = var.location
  resource_group_name = azurerm_resource_group.spokes[each.key].name
  address_space       = [each.value.address_space]
  tags                = merge(var.common_tags, { role = "spoke", environment = each.key })
  depends_on          = [azurerm_resource_group.spokes]
}

# =============================================================
# SUBNETS — existing
# =============================================================
resource "azurerm_subnet" "hub" {
  for_each             = local.hub_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value.address_prefix]
  depends_on           = [azurerm_virtual_network.hub]
}

resource "azurerm_subnet" "spokes" {
  for_each             = local.spoke_subnets
  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.spokes[each.value.spoke_key].name
  virtual_network_name = azurerm_virtual_network.spokes[each.value.spoke_key].name
  address_prefixes     = [each.value.address_prefix]

  dynamic "delegation" {
    for_each = each.value.snet_key == "appservice" ? [1] : []
    content {
      name = "delegation-appservice"
      service_delegation {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }

  dynamic "delegation" {
    for_each = each.value.snet_key == "database" ? [1] : []
    content {
      name = "delegation-postgres"
      service_delegation {
        name    = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

  depends_on = [azurerm_virtual_network.spokes]
}

# =============================================================
# PEERING — existing
# =============================================================
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = local.peering_spokes
  name                         = "hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spokes[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network.hub, azurerm_virtual_network.spokes]
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = local.peering_spokes
  name                         = "${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.spokes[each.key].name
  virtual_network_name         = azurerm_virtual_network.spokes[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
  depends_on                   = [azurerm_virtual_network.hub, azurerm_virtual_network.spokes]
}
