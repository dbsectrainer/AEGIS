# Azure Government Provider Configuration
provider "azurerm" {
  features {}

  # Azure Government specific configurations
  environment = "usgovernment"

  # Use managed identity if specified
  use_msi = var.use_managed_identity

  # Subscription configuration
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Azure Provider Variables
variable "subscription_id" {
  description = "Azure Government subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Government tenant ID"
  type        = string
}

variable "use_managed_identity" {
  description = "Use managed identity for authentication"
  type        = bool
  default     = false
}

variable "location" {
  description = "Azure Government region to deploy resources"
  type        = string
  default     = "usgovvirginia"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "gov-cloud-rg"
}

variable "default_tags" {
  description = "Default tags for all Azure resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "gov-cloud"
  }
}

# Azure Backend Configuration for State Management
terraform {
  backend "azurerm" {
    resource_group_name  = "gov-terraform-state-rg"
    storage_account_name = "govterraformstate"
    container_name       = "tfstate"
    key                  = "government.tfstate"
    environment          = "usgovernment"
  }
}

# Data sources for Azure configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.default_tags
}

# Outputs
output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}
