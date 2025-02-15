# Southeast Region Production Environment

# AWS Resources
module "aws_networking" {
  source = "../../../modules/networking/aws"

  environment          = "prod-southeast"
  region              = "us-gov-east-1"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  availability_zones   = ["us-gov-east-1a", "us-gov-east-1b"]

  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# AWS Compute Resources
module "aws_compute" {
  source = "../../../modules/compute/aws"

  environment          = "prod-southeast"
  vpc_id              = module.aws_networking.vpc_id
  private_subnet_ids  = module.aws_networking.private_subnet_ids
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  
  kubernetes_version  = "1.27"
  ssh_key_name       = "uscg-prod-southeast"
  kms_key_arn        = "arn:aws-us-gov:kms:us-gov-east-1:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd5678"
  
  ecs_ami_id         = "ami-123456789" # Replace with actual ECS-optimized AMI ID
  
  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# Azure Government Configuration
module "azure_networking" {
  source = "../../../modules/networking/azure"

  environment         = "prod-southeast"
  location           = "usgovvirginia"
  resource_group_name = "uscg-prod-southeast-rg"
  vnet_cidr          = "172.16.0.0/16"
  public_subnet_cidrs = ["172.16.1.0/24", "172.16.2.0/24"]
  private_subnet_cidrs = ["172.16.3.0/24", "172.16.4.0/24"]

  enable_nat_gateway = true
  enable_private_link = true

  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# Azure Compute Resources
module "azure_compute" {
  source = "../../../modules/compute/azure"

  environment          = "prod-southeast"
  location            = "usgovvirginia"
  resource_group_name = "uscg-prod-southeast-rg"
  subnet_id           = module.azure_networking.private_subnet_ids[0]
  
  kubernetes_version  = "1.27"
  admin_group_object_ids = ["12345678-1234-5678-1234-567812345678"] # Replace with actual Azure AD group IDs
  
  allowed_ip_ranges  = "10.0.0.0/8"
  key_vault_key_id   = "/subscriptions/12345678-1234-5678-1234-567812345678/resourceGroups/uscg-prod-southeast-rg/providers/Microsoft.KeyVault/vaults/uscg-prod-kv/keys/container-registry"
  
  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# GCP Configuration
module "gcp_networking" {
  source = "../../../modules/networking/gcp"

  environment         = "prod-southeast"
  project_id         = var.gcp_project_id
  region             = "us-east4"
  public_subnet_cidrs = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnet_cidrs = ["192.168.3.0/24", "192.168.4.0/24"]

  enable_vpc_sc = true
  access_policy_id = var.gcp_access_policy_id
  project_number = var.gcp_project_number

  enable_private_service_connect = true
}

# GCP Compute Resources
module "gcp_compute" {
  source = "../../../modules/compute/gcp"

  environment          = "prod-southeast"
  project_id          = var.gcp_project_id
  region              = "us-east4"
  network_id          = module.gcp_networking.network_id
  subnetwork_id       = module.gcp_networking.private_subnet_ids[0]
  
  master_ipv4_cidr_block     = "172.16.0.0/28"
  cluster_ipv4_cidr_block    = "10.4.0.0/16"
  services_ipv4_cidr_block   = "10.5.0.0/16"
  
  master_authorized_networks = [
    {
      cidr_block   = "10.0.0.0/8"
      display_name = "VPC Network"
    }
  ]
  
  network_usage_dataset_id = "network_usage_dataset"
}

# AWS Database Resources
module "aws_database" {
  source = "../../../modules/database/aws"

  environment          = "prod-southeast"
  vpc_id              = module.aws_networking.vpc_id
  subnet_ids          = module.aws_networking.private_subnet_ids
  allowed_security_groups = [module.aws_compute.ecs_security_group_id]

  create_aurora_cluster = true
  database_name        = "uscgapp"
  master_username      = "admin"
  master_password      = var.aurora_master_password

  dynamodb_tables = {
    audit_logs = {
      billing_mode = "PAY_PER_REQUEST"
      hash_key     = "id"
      range_key    = "timestamp"
      attributes = [
        {
          name = "id"
          type = "S"
        },
        {
          name = "timestamp"
          type = "S"
        }
      ]
    }
  }

  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# Azure Database Resources
module "azure_database" {
  source = "../../../modules/database/azure"

  environment          = "prod-southeast"
  location            = "usgovvirginia"
  resource_group_name = "uscg-prod-southeast-rg"
  subnet_id           = module.azure_networking.private_subnet_ids[0]
  
  administrator_login    = "admin"
  administrator_password = var.azure_sql_password
  
  azure_ad_admin_username  = var.azure_ad_admin_username
  azure_ad_admin_object_id = var.azure_ad_admin_object_id

  private_dns_zone_id = var.azure_private_dns_zone_id
  log_analytics_workspace_id = var.azure_log_analytics_workspace_id

  tags = {
    Environment = "production"
    Region      = "southeast"
    ManagedBy   = "terraform"
  }
}

# GCP Database Resources
module "gcp_database" {
  source = "../../../modules/database/gcp"

  environment = "prod-southeast"
  project_id  = var.gcp_project_id
  region      = "us-east4"
  network_id  = module.gcp_networking.network_id

  database_user     = "admin"
  database_password = var.gcp_db_password
  sql_ip_range     = "10.6.0.0/16"

  create_spanner = true
  spanner_config = "regional-us-east1"
  spanner_processing_units = 1000

  notification_channels = var.gcp_notification_channels

  labels = {
    environment = "production"
    region      = "southeast"
    managed_by  = "terraform"
  }
}

# Cross-Cloud Network Connectivity (if required)
# Note: Implementation depends on specific requirements and connectivity methods
# Examples include AWS Direct Connect, Azure ExpressRoute, GCP Cloud Interconnect

# Database Variables
variable "aurora_master_password" {
  description = "Master password for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "azure_sql_password" {
  description = "Password for Azure SQL administrator"
  type        = string
  sensitive   = true
}

variable "azure_ad_admin_username" {
  description = "Azure AD admin username for SQL Server"
  type        = string
}

variable "azure_ad_admin_object_id" {
  description = "Azure AD admin object ID for SQL Server"
  type        = string
}

variable "azure_private_dns_zone_id" {
  description = "Azure Private DNS Zone ID"
  type        = string
}

variable "azure_log_analytics_workspace_id" {
  description = "Azure Log Analytics Workspace ID"
  type        = string
}

variable "gcp_db_password" {
  description = "Password for GCP database user"
  type        = string
  sensitive   = true
}

variable "gcp_notification_channels" {
  description = "GCP monitoring notification channel IDs"
  type        = list(string)
}

# Project Variables
variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_access_policy_id" {
  description = "GCP Access Policy ID for VPC Service Controls"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP Project Number"
  type        = string
}

# Outputs
# AWS Outputs
output "aws_vpc_id" {
  value = module.aws_networking.vpc_id
}

output "aws_private_subnet_ids" {
  value = module.aws_networking.private_subnet_ids
}

output "aws_eks_cluster_id" {
  value = module.aws_compute.eks_cluster_id
}

output "aws_ecs_cluster_id" {
  value = module.aws_compute.ecs_cluster_id
}

# Azure Outputs
output "azure_vnet_id" {
  value = module.azure_networking.vnet_id
}

output "azure_private_subnet_ids" {
  value = module.azure_networking.private_subnet_ids
}

output "azure_aks_cluster_id" {
  value = module.azure_compute.aks_cluster_id
}

output "azure_acr_id" {
  value = module.azure_compute.acr_id
}

# GCP Outputs
output "gcp_network_id" {
  value = module.gcp_networking.network_id
}

output "gcp_private_subnet_ids" {
  value = module.gcp_networking.private_subnet_ids
}

output "gcp_gke_cluster_id" {
  value = module.gcp_compute.cluster_id
}

output "gcp_artifact_registry_id" {
  value = module.gcp_compute.artifact_registry_id
}

# Database Outputs
output "aurora_cluster_endpoint" {
  value = module.aws_database.aurora_cluster_endpoint
}

output "aurora_cluster_reader_endpoint" {
  value = module.aws_database.aurora_cluster_reader_endpoint
}

output "azure_sql_server_name" {
  value = module.azure_database.sql_server_name
}

output "azure_cosmos_endpoint" {
  value = module.azure_database.cosmos_account_endpoint
}

output "gcp_sql_instance_name" {
  value = module.gcp_database.sql_instance_name
}

output "gcp_spanner_instance_id" {
  value = module.gcp_database.spanner_instance_id
}

# Provider Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }

  # Use remote state
  backend "s3" {
    bucket         = "uscg-terraform-state"
    key            = "environments/production/southeast/terraform.tfstate"
    region         = "us-gov-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Provider configurations are inherited from the provider configurations in terraform/providers/
