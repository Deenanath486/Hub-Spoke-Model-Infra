# =============================================================
# providers.tf — Hub-Spoke Model
# =============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100.0"
    }
  }

  # Backend — state file Azure Storage mein store hoga (optional)
  # Uncomment karo agar remote state chahiye
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "devyanitfstate"
  #   container_name       = "tfstate"
  #   key                  = "hub-spoke.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {
    resource_group {
      # RG delete karne pe andar ke resources bhi delete honge
      prevent_deletion_if_contains_resources = false
    }

    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }

    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  # Authentication — environment variables se hogi
  # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  # Ya Azure CLI login: az login
}
