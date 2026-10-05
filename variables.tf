# =============================================================
# variables.tf
# =============================================================

variable "location" {
  type    = string
  default = "East US"
}

variable "project_name" {
  type    = string
  default = "Devyani"
}

# Devyani-RG — existing RG, new resources jayenge yahan
variable "resource_group_name" {
  type    = string
  default = "Devyani-RG"
}

# =============================================================
# HUB — rg-hub mein already bana hua
# =============================================================
variable "hub_config" {
  type = object({
    name           = string
    address_space  = string
    resource_group = string
    subnets = map(object({
      name           = string
      address_prefix = string
    }))
  })
  default = {
    name           = "Devyani-Hub"
    address_space  = "10.0.0.0/16"
    resource_group = "rg-hub"
    subnets = {
      firewall = { name = "AzureFirewallSubnet", address_prefix = "10.0.1.0/24" }
      bastion  = { name = "AzureBastionSubnet", address_prefix = "10.0.2.0/24" }
      appgw    = { name = "AppGatewaySubnet", address_prefix = "10.0.3.0/24" }
      gateway  = { name = "GatewaySubnet", address_prefix = "10.0.4.0/24" }
    }
  }
}

variable "enable_gateway_subnet" {
  type    = bool
  default = true # already bana hua hai state mein
}

variable "gateway_subnet_prefix" {
  type    = string
  default = "10.0.4.0/24"
}

# =============================================================
# SPOKES — rg-dev, rg-prod mein already bane hue
# =============================================================
variable "spoke_configs" {
  type = map(object({
    name           = string
    address_space  = string
    resource_group = string
    subnets = map(object({
      name           = string
      address_prefix = string
    }))
  }))
  default = {
    dev = {
      name           = "Devyani-Dev"
      address_space  = "10.20.0.0/16"
      resource_group = "rg-dev"
      subnets = {
        frontend   = { name = "dev-frontend-subnet", address_prefix = "10.20.1.0/24" }
        backend    = { name = "dev-backend-subnet", address_prefix = "10.20.2.0/24" }
        database   = { name = "dev-database-subnet", address_prefix = "10.20.3.0/24" }
        appservice = { name = "dev-appservice-snet", address_prefix = "10.20.4.0/24" }
      }
    }
    prod = {
      name           = "Devyani-Prod"
      address_space  = "10.10.0.0/16"
      resource_group = "rg-prod"
      subnets = {
        frontend   = { name = "prod-frontend-subnet", address_prefix = "10.10.1.0/24" }
        backend    = { name = "prod-backend-subnet", address_prefix = "10.10.2.0/24" }
        database   = { name = "prod-database-subnet", address_prefix = "10.10.3.0/24" }
        appservice = { name = "prod-appservice-snet", address_prefix = "10.10.4.0/24" }
      }
    }
  }
}

# =============================================================
# APP SERVICES
# =============================================================
variable "app_services" {
  type = map(object({
    tier    = string
    runtime = string
  }))
  default = {
    frontend = { tier = "frontend", runtime = "NODE|18-lts" }
    backend  = { tier = "backend", runtime = "PYTHON|3.11" }
  }
}

variable "app_service_plan_sku" {
  type = map(string)
  default = {
    dev  = "B2"
    prod = "P2v3"
  }
}

# =============================================================
# POSTGRESQL
# =============================================================
variable "postgres_config" {
  type = map(object({
    sku_name              = string
    pg_version            = string
    storage_mb            = number
    db_name               = string
    backup_retention_days = number
    geo_redundant_backup  = bool
    high_availability     = bool
  }))
  default = {
    dev = {
      sku_name              = "B_Standard_B1ms"
      pg_version            = "15"
      storage_mb            = 32768
      db_name               = "devdb"
      backup_retention_days = 7
      geo_redundant_backup  = false
      high_availability     = false
    }
    prod = {
      sku_name              = "GP_Standard_D2s_v3"
      pg_version            = "15"
      storage_mb            = 65536
      db_name               = "proddb"
      backup_retention_days = 30
      geo_redundant_backup  = true
      high_availability     = true
    }
  }
}

variable "postgres_admin_user" {
  type      = string
  default   = "pgadmin"
  sensitive = true
}

variable "postgres_admin_password" {
  type      = string
  default   = "P@ssw0rd#PG2024!"
  sensitive = true
}

# =============================================================
# HUB SERVICES
# =============================================================
variable "firewall_config" {
  type = object({
    name     = string
    sku_name = string
    sku_tier = string
  })
  default = {
    name     = "hub-firewall"
    sku_name = "AZFW_VNet"
    sku_tier = "Standard"
  }
}

variable "bastion_config" {
  type = object({
    name = string
    sku  = string
  })
  default = {
    name = "hub-bastion"
    sku  = "Standard"
  }
}

variable "app_gateway_config" {
  type = object({
    name     = string
    sku_name = string
    sku_tier = string
    capacity = number
  })
  default = {
    name     = "hub-appgw"
    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"
    capacity = 2
  }
}

variable "ssl_certificate_path" {
  type    = string
  default = ""
}

variable "ssl_certificate_password" {
  type      = string
  sensitive = true
  default   = ""
}

# =============================================================
# OBSERVABILITY
# =============================================================
variable "log_analytics_retention_days" {
  type    = number
  default = 30
}

variable "key_vault_sku" {
  type    = string
  default = "standard"
}

variable "enable_front_door" {
  type    = bool
  default = false
}

# =============================================================
# TAGS
# =============================================================
variable "common_tags" {
  type = map(string)
  default = {
    project    = "Devyani-Hub-Spoke"
    owner      = "Devyani"
    managed_by = "Terraform"
  }
}
