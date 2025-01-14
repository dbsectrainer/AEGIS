# Variables for USCG Multi-Cloud Infrastructure

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "region" {
  description = "Region name (e.g., southeast, northeast)"
  type        = string
  default     = "southeast"
}

variable "aws_govcloud_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-east-1"
}

variable "azure_gov_region" {
  description = "Azure Government region"
  type        = string
  default     = "usgovvirginia"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "172.16.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "azure_subnet_cidrs" {
  description = "CIDR blocks for Azure subnets"
  type        = list(string)
  default     = ["172.16.1.0/24", "172.16.2.0/24"]
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Organization = "USCG"
    Environment  = "Production"
    Compliance  = "FedRAMP-High"
  }
}

variable "dx_gateway_asn" {
  description = "ASN for Direct Connect Gateway"
  type        = string
  default     = "64512"
}

variable "expressroute_bandwidth" {
  description = "Bandwidth in Mbps for ExpressRoute circuit"
  type        = number
  default     = 1000
}

variable "expressroute_provider" {
  description = "Service provider for ExpressRoute"
  type        = string
  default     = "Equinix"
}

variable "expressroute_peering_location" {
  description = "Peering location for ExpressRoute"
  type        = string
  default     = "Washington DC"
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 90
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "premium"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "GRS"
}

# Security-related variables
variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for management access"
  type        = list(string)
  default     = []  # Should be provided in terraform.tfvars
}

variable "enable_encryption" {
  description = "Enable encryption for all supported resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable logging for all supported resources"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring for all supported resources"
  type        = bool
  default     = true
}

# Compliance-related variables
variable "compliance_requirements" {
  description = "List of compliance requirements to enforce"
  type        = list(string)
  default     = ["FedRAMP-High", "NIST-800-53", "DoD-SRG"]
}

variable "data_classification" {
  description = "Data classification level"
  type        = string
  default     = "sensitive"
}

# Backup and DR variables
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 90
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = true
}

# Performance-related variables
variable "performance_tier" {
  description = "Performance tier for resources"
  type        = string
  default     = "premium"
}

variable "auto_scaling_enabled" {
  description = "Enable auto-scaling for supported resources"
  type        = bool
  default     = true
}
