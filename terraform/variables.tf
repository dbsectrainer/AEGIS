# USCG Multi-Cloud IAM Variables

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-east-1"
}

variable "azure_location" {
  description = "Azure Government location"
  type        = string
  default     = "usgovvirginia"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "uscg"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {
    Environment = "production"
    Project     = "USCG"
    ManagedBy   = "Terraform"
    Security    = "FedRAMP-High"
  }
}

variable "password_policy" {
  description = "IAM password policy settings"
  type = object({
    minimum_length        = number
    require_lowercase     = bool
    require_uppercase     = bool
    require_numbers       = bool
    require_symbols       = bool
    password_reuse_limit  = number
    max_password_age      = number
  })
  default = {
    minimum_length        = 14
    require_lowercase     = true
    require_uppercase     = true
    require_numbers       = true
    require_symbols       = true
    password_reuse_limit  = 24
    max_password_age      = 60
  }
}

variable "emergency_access" {
  description = "Emergency access configuration"
  type = object({
    user_path  = string
    group_path = string
  })
  default = {
    user_path  = "/system/"
    group_path = "/emergency/"
  }
}

variable "audit_log_retention_days" {
  description = "Number of days to retain audit logs"
  type        = number
  default     = 365
}

variable "session_timeout" {
  description = "Session timeout in hours"
  type        = number
  default     = 1
}

variable "key_vault" {
  description = "Key Vault configuration"
  type = object({
    sku_name                    = string
    soft_delete_retention_days  = number
    purge_protection_enabled    = bool
  })
  default = {
    sku_name                    = "premium"
    soft_delete_retention_days  = 90
    purge_protection_enabled    = true
  }
}

variable "log_analytics" {
  description = "Log Analytics configuration"
  type = object({
    sku               = string
    retention_in_days = number
  })
  default = {
    sku               = "PerGB2018"
    retention_in_days = 90
  }
}

variable "storage_account" {
  description = "Storage Account configuration"
  type = object({
    account_tier             = string
    account_replication_type = string
    min_tls_version         = string
  })
  default = {
    account_tier             = "Standard"
    account_replication_type = "GRS"
    min_tls_version         = "TLS1_2"
  }
}

# Azure AD Conditional Access Policy Settings
variable "conditional_access" {
  description = "Conditional Access Policy configuration"
  type = object({
    state                     = string
    client_app_types         = list(string)
    sign_in_frequency        = number
    sign_in_frequency_period = string
  })
  default = {
    state                     = "enabled"
    client_app_types         = ["all"]
    sign_in_frequency        = 1
    sign_in_frequency_period = "hours"
  }
}

# Service Principal Names
variable "service_principals" {
  description = "List of service principals to create"
  type        = list(string)
  default     = []
}

# RBAC Role Assignments
variable "role_assignments" {
  description = "Map of role assignments"
  type = map(object({
    role_definition_name = string
    principal_type      = string
  }))
  default = {}
}
