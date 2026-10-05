# =============================================================
# terraform.tfvars
# =============================================================

location            = "East US"
project_name        = "Devyani"
resource_group_name = "Devyani-RG"

postgres_admin_user     = "pgadmin"
postgres_admin_password = "P@ssw0rd#PG2024!"

app_service_plan_sku = {
  dev  = "B2"
  prod = "P2v3"
}

log_analytics_retention_days = 30
key_vault_sku                = "standard"
enable_gateway_subnet        = false
enable_front_door            = false

common_tags = {
  project    = "Devyani-Hub-Spoke"
  owner      = "Devyani"
  managed_by = "Terraform"
}
