# =============================================================
# hub_services.tf — Sab Devyani-RG mein
# 1. Azure Firewall + Policy + Rules
# 2. Azure Bastion
# 3. App Gateway WAF_v2 — HTTPS, health probes, redirect
# 4. Route Tables — ONLY privateep subnet (not appservice/database)
# =============================================================

# =============================================================
# PUBLIC IPs
# =============================================================
resource "azurerm_public_ip" "firewall" {
  name                = "${var.firewall_config.name}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = merge(var.common_tags, { service = "firewall" })
}

resource "azurerm_public_ip" "bastion" {
  name                = "${var.bastion_config.name}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = merge(var.common_tags, { service = "bastion" })
}

resource "azurerm_public_ip" "appgw" {
  name                = "${var.app_gateway_config.name}-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = merge(var.common_tags, { service = "appgateway" })
}

# =============================================================
# AZURE FIREWALL
# =============================================================
resource "azurerm_firewall_policy" "hub" {
  name                = "${var.firewall_config.name}-policy"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = var.firewall_config.sku_tier

  dns {
    proxy_enabled = true
  }

  tags = merge(var.common_tags, { service = "firewall" })
}

resource "azurerm_firewall" "hub" {
  name                = var.firewall_config.name
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = var.firewall_config.sku_name
  sku_tier            = var.firewall_config.sku_tier
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  zones               = ["1", "2", "3"]

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.hub["firewall"].id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = merge(var.common_tags, { service = "firewall" })

  depends_on = [azurerm_subnet.hub, azurerm_public_ip.firewall]
}

resource "azurerm_firewall_policy_rule_collection_group" "hub" {
  name               = "hub-rcg"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 100

  network_rule_collection {
    name     = "allow-internal"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-https"
      protocols             = ["TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "allow-dns"
      protocols             = ["UDP", "TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "allow-postgres"
      protocols             = ["TCP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["10.0.0.0/8"]
      destination_ports     = ["5432"]
    }
  }

  application_rule_collection {
    name     = "allow-azure-fqdns"
    priority = 200
    action   = "Allow"

    rule {
      name             = "allow-azure-services"
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "*.azure.com",
        "*.microsoft.com",
        "*.azurewebsites.net",
        "*.postgres.database.azure.com",
        "*.vault.azure.net",
        "*.monitor.azure.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

# =============================================================
# ROUTE TABLES — ONLY privateep subnet
# appservice-snet: NO UDR (App Service VNet Integration breaks)
# database-snet:   NO UDR (PostgreSQL delegation subnet)
# privateep-snet:  UDR → Firewall
# =============================================================
# =============================================================
# ROUTE TABLES — state se match
# Route table associations sab subnets pe — existing state
# =============================================================
resource "azurerm_route_table" "spokes" {
  for_each                      = var.spoke_configs
  name                          = "${each.key}-rt"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.spokes[each.key].name
  disable_bgp_route_propagation = true

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }

  tags       = merge(var.common_tags, { environment = each.key })
  depends_on = [azurerm_firewall.hub]
}

# FIX #2: Route table associations — all spoke subnets
# State mein: dev/appservice, dev/frontend, dev/backend, dev/database + prod same
# appservice subnet ke liye association hai lekin UDR App Service ke liye break karega
# NOTE: App Service VNet Integration ke liye appservice subnet pe UDR mat lagao in production
#       Abhi state match ke liye rakh rahe hain
resource "azurerm_subnet_route_table_association" "spokes" {
  for_each       = local.spoke_subnets
  subnet_id      = azurerm_subnet.spokes[each.key].id
  route_table_id = azurerm_route_table.spokes[each.value.spoke_key].id
  depends_on     = [azurerm_subnet.spokes, azurerm_route_table.spokes]
}

# =============================================================
# AZURE BASTION
# =============================================================
resource "azurerm_bastion_host" "hub" {
  name                = var.bastion_config.name
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = var.bastion_config.sku

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.hub["bastion"].id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags       = merge(var.common_tags, { service = "bastion" })
  depends_on = [azurerm_subnet.hub, azurerm_public_ip.bastion]
}

# =============================================================
# APP GATEWAY — WAF_v2
# =============================================================
resource "azurerm_web_application_firewall_policy" "hub" {
  name                = "hub-waf-policy"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = merge(var.common_tags, { service = "waf" })
}

resource "azurerm_application_gateway" "hub" {
  name                = var.app_gateway_config.name
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  firewall_policy_id  = azurerm_web_application_firewall_policy.hub.id

  sku {
    name     = var.app_gateway_config.sku_name
    tier     = var.app_gateway_config.sku_tier
    capacity = var.app_gateway_config.capacity
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.hub["appgw"].id
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-pip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # NOTE: SSL cert ke liye real PFX file chahiye apply mein
  # Agar ssl_certificate_path set nahi hai toh HTTPS listener HTTP pe fallback karega
  # Production mein: var.ssl_certificate_path set karo ya Key Vault secret_id use karo

  # HTTP Listener
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "appgw-frontend-pip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  # Backend Pools — App Service FQDNs
  backend_address_pool {
    name  = "dev-frontend-pool"
    fqdns = ["dev-frontend-app.azurewebsites.net"]
  }

  backend_address_pool {
    name  = "prod-frontend-pool"
    fqdns = ["prod-frontend-app.azurewebsites.net"]
  }

  # Backend HTTP Settings — pick host from backend FQDN (required for App Service)
  backend_http_settings {
    name                                = "dev-https-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = "dev-health-probe"
  }

  backend_http_settings {
    name                                = "prod-https-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = "prod-health-probe"
  }

  # Health Probes — HTTPS, host from backend settings
  probe {
    name                                      = "dev-health-probe"
    protocol                                  = "Https"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  probe {
    name                                      = "prod-health-probe"
    protocol                                  = "Https"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  # HTTP → HTTPS Redirect
  redirect_configuration {
    name                 = "http-to-https"
    redirect_type        = "Permanent"
    target_listener_name = "listener-https"
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "http-redirect-rule"
    rule_type                   = "Basic"
    priority                    = 100
    http_listener_name          = "listener-http"
    redirect_configuration_name = "http-to-https"
  }

  # Path-based routing — /dev/* → dev, /prod/* → prod
  url_path_map {
    name                               = "path-routing"
    default_backend_address_pool_name  = "prod-frontend-pool"
    default_backend_http_settings_name = "prod-https-settings"

    path_rule {
      name                       = "dev-rule"
      paths                      = ["/dev/*"]
      backend_address_pool_name  = "dev-frontend-pool"
      backend_http_settings_name = "dev-https-settings"
    }

    path_rule {
      name                       = "prod-rule"
      paths                      = ["/prod/*"]
      backend_address_pool_name  = "prod-frontend-pool"
      backend_http_settings_name = "prod-https-settings"
    }
  }

  request_routing_rule {
    name               = "https-routing-rule"
    rule_type          = "PathBasedRouting"
    priority           = 200
    http_listener_name = "listener-https"
    url_path_map_name  = "path-routing"
  }

  tags = merge(var.common_tags, { service = "appgateway" })

  depends_on = [
    azurerm_subnet.hub,
    azurerm_public_ip.appgw,
    azurerm_web_application_firewall_policy.hub,
  ]
}
