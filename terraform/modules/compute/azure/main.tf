# Azure Compute Module

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.environment}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.environment}-aks"
  kubernetes_version  = var.kubernetes_version

  # Keep the API server off the public internet
  private_cluster_enabled = true

  default_node_pool {
    name                 = "system"
    node_count           = var.system_node_count
    vm_size              = var.system_node_vm_size
    vnet_subnet_id       = var.subnet_id
    zones                = var.availability_zones
    auto_scaling_enabled = true
    min_count            = var.system_node_min_count
    max_count            = var.system_node_max_count
    os_disk_size_gb      = var.system_node_disk_size
    os_disk_type         = "Managed"
    type                 = "VirtualMachineScaleSets"

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "nodetype"      = "system"
    }

    tags = var.tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "Standard"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  azure_policy_enabled = true

  tags = var.tags
}

# Additional Node Pool
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  vnet_subnet_id        = var.subnet_id
  zones                 = var.availability_zones
  auto_scaling_enabled  = true
  min_count             = var.user_node_min_count
  max_count             = var.user_node_max_count
  os_disk_size_gb       = var.user_node_disk_size
  os_type               = "Linux"
  mode                  = "User"

  node_labels = {
    "nodepool-type" = "user"
    "environment"   = var.environment
    "nodetype"      = "user"
  }

  tags = var.tags
}

# Container Registry
resource "azurerm_container_registry" "main" {
  name                = replace("${var.environment}acr", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false

  network_rule_set {
    default_action = "Deny"
    ip_rule {
      action   = "Allow"
      ip_range = var.allowed_ip_ranges
    }
  }

  encryption {
    key_vault_key_id   = var.key_vault_key_id
    identity_client_id = azurerm_user_assigned_identity.acr.client_id
  }

  tags = var.tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.environment}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# Container Insights Solution
resource "azurerm_log_analytics_solution" "containers" {
  solution_name         = "Containers"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  workspace_name        = azurerm_log_analytics_workspace.main.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Containers"
  }
}

# Managed Identity for ACR
resource "azurerm_user_assigned_identity" "acr" {
  name                = "${var.environment}-acr-identity"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for AKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "system_node_count" {
  description = "Number of system nodes"
  type        = number
  default     = 3
}

variable "system_node_vm_size" {
  description = "VM size for system nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_min_count" {
  description = "Minimum number of system nodes"
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum number of system nodes"
  type        = number
  default     = 5
}

variable "system_node_disk_size" {
  description = "Disk size for system nodes"
  type        = number
  default     = 128
}

variable "user_node_count" {
  description = "Number of user nodes"
  type        = number
  default     = 2
}

variable "user_node_vm_size" {
  description = "VM size for user nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "user_node_min_count" {
  description = "Minimum number of user nodes"
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum number of user nodes"
  type        = number
  default     = 10
}

variable "user_node_disk_size" {
  description = "Disk size for user nodes"
  type        = number
  default     = 128
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "admin_group_object_ids" {
  description = "Azure AD group object IDs for cluster admin access"
  type        = list(string)
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "allowed_ip_ranges" {
  description = "Allowed IP ranges for ACR access"
  type        = string
}

variable "key_vault_key_id" {
  description = "Key Vault key ID for ACR encryption"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "aks_cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_fqdn" {
  value = azurerm_kubernetes_cluster.main.fqdn
}

output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.acr.id
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.acr.client_id
}
