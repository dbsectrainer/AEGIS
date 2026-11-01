# AEGIS production root variables.
# Secrets and tenant-specific identifiers have no defaults and must be supplied at
# plan/apply time (for example through TF_VAR_* environment variables).

variable "environment_name" {
  description = "Deployment/environment label used in resource names"
  type        = string
  default     = "prod-southeast"
}

variable "default_tags" {
  description = "Tags applied to AWS resources and reused as module tags"
  type        = map(string)
  default = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
    Project     = "aegis"
  }
}

# AWS
variable "aws_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-east-1"
}

variable "aws_availability_zones" {
  description = "Availability zones used by the AWS networking module"
  type        = list(string)
  default     = ["us-gov-east-1a", "us-gov-east-1b"]

  validation {
    condition = length(var.aws_availability_zones) >= max(
      length(var.aws_public_subnet_cidrs),
      length(var.aws_private_subnet_cidrs)
    )
    error_message = "aws_availability_zones must provide one zone for every public and private subnet."
  }
}

variable "vpc_cidr" {
  description = "AWS VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_public_subnet_cidrs" {
  description = "AWS public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "aws_private_subnet_cidrs" {
  description = "AWS private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS, AKS, and GKE"
  type        = string
  default     = "1.35"
}

variable "ecs_ami_id" {
  description = "ECS-optimized AMI ID for the AWS GovCloud region"
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ecs_ami_id))
    error_message = "ecs_ami_id must be an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "ecs_instance_type" {
  description = "EC2 instance type for the ECS auto scaling group"
  type        = string
  default     = "m5.large"
}

variable "node_group_desired_size" {
  description = "Desired EKS managed node group size"
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Minimum EKS managed node group size"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum EKS managed node group size"
  type        = number
  default     = 4
}

variable "ecs_desired_capacity" {
  description = "Desired ECS auto scaling group capacity"
  type        = number
  default     = 2
}

variable "ecs_min_size" {
  description = "Minimum ECS auto scaling group capacity"
  type        = number
  default     = 1
}

variable "ecs_max_size" {
  description = "Maximum ECS auto scaling group capacity"
  type        = number
  default     = 4
}

# Azure
variable "azure_subscription_id" {
  description = "Azure Government subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure Government tenant ID"
  type        = string
}

variable "azure_location" {
  description = "Azure Government region"
  type        = string
  default     = "usgovvirginia"
}

variable "azure_resource_group" {
  description = "Resource group for all Azure resources"
  type        = string
  default     = "gov-prod-southeast-rg"
}

variable "vnet_cidr" {
  description = "Azure virtual network CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "azure_public_subnet_cidrs" {
  description = "Azure public subnet CIDRs"
  type        = list(string)
  default     = ["172.16.1.0/24", "172.16.2.0/24"]
}

variable "azure_private_subnet_cidrs" {
  description = "Azure private subnet CIDRs"
  type        = list(string)
  default     = ["172.16.3.0/24", "172.16.4.0/24"]
}

variable "azure_public_ingress_source_prefixes" {
  description = "Source prefixes allowed to reach the Azure public NSG on 443"
  type        = list(string)
  default     = ["VirtualNetwork"]
}

variable "azure_key_vault_key_id" {
  description = "Key Vault key ID used for ACR encryption"
  type        = string
}

variable "azure_admin_group_object_ids" {
  description = "Azure AD group object IDs granted AKS cluster admin"
  type        = list(string)
}

variable "allowed_ip_ranges" {
  description = "CIDR allowed to reach the Azure container registry"
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition     = can(cidrhost(var.allowed_ip_ranges, 0))
    error_message = "allowed_ip_ranges must be a valid CIDR block."
  }
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP project number"
  type        = string
}

variable "gcp_access_policy_id" {
  description = "GCP access policy ID for VPC Service Controls"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-east4"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "us-east4-a"
}

variable "gcp_public_subnet_cidrs" {
  description = "GCP public subnet CIDRs"
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24"]
}

variable "gcp_private_subnet_cidrs" {
  description = "GCP private subnet CIDRs"
  type        = list(string)
  default     = ["192.168.3.0/24", "192.168.4.0/24"]
}

variable "gcp_master_cidr" {
  description = "GCP GKE control plane CIDR"
  type        = string
  default     = "172.16.0.0/28"
}

variable "gcp_cluster_cidr" {
  description = "GCP GKE pod CIDR"
  type        = string
  default     = "10.4.0.0/16"
}

variable "gcp_services_cidr" {
  description = "GCP GKE service CIDR"
  type        = string
  default     = "10.5.0.0/16"
}

variable "gcp_network_usage_dataset_id" {
  description = "BigQuery dataset ID used for GKE network usage export"
  type        = string
  default     = "network_usage_dataset"
}

variable "gcp_notification_channels" {
  description = "GCP monitoring notification channel IDs"
  type        = list(string)
  default     = []
}

# Database credentials
variable "aurora_master_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "azure_sql_password" {
  description = "Administrator password for Azure SQL"
  type        = string
  sensitive   = true
}

variable "gcp_db_password" {
  description = "Password for the GCP database user"
  type        = string
  sensitive   = true
}

variable "azure_ad_admin_username" {
  description = "Azure AD administrator login for Azure SQL"
  type        = string
}

variable "azure_ad_admin_object_id" {
  description = "Azure AD administrator object ID for Azure SQL"
  type        = string
}
