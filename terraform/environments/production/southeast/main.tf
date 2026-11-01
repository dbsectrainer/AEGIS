# Southeast Region Production Environment
# Multi-cloud root module for AWS GovCloud, Azure Government, and GCP.
# Provider configuration lives in providers.tf; inputs in variables.tf.

locals {
  gcp_labels = {
    environment = "production"
    region      = "southeast"
    managed_by  = "terraform"
    project     = "aegis"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.azure_resource_group
  location = var.azure_location
  tags     = var.default_tags
}

# AWS KMS key shared by EKS secrets encryption and ECS execute-command logging.
# The key policy is the AWS-created root policy; the EKS role receives an
# explicit identity policy in modules/compute/aws/iam.tf.
resource "aws_kms_key" "platform" {
  description             = "AEGIS platform encryption key (${var.environment_name})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.default_tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.environment_name}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

# Azure Private DNS zones for private endpoints. Azure Government zone names
# follow the Microsoft private-endpoint DNS reference.
resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.us"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "sql-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = module.azure_networking.vnet_id
  registration_enabled  = false
  tags                  = var.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "cosmos-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = module.azure_networking.vnet_id
  registration_enabled  = false
  tags                  = var.default_tags
}

# AWS Resources
module "aws_networking" {
  source = "../../../modules/networking/aws"

  environment          = var.environment_name
  region               = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.aws_public_subnet_cidrs
  private_subnet_cidrs = var.aws_private_subnet_cidrs
  availability_zones   = var.aws_availability_zones

  tags = var.default_tags
}

module "aws_compute" {
  source = "../../../modules/compute/aws"

  environment          = var.environment_name
  vpc_id               = module.aws_networking.vpc_id
  private_subnet_ids   = module.aws_networking.private_subnet_ids
  private_subnet_cidrs = var.aws_private_subnet_cidrs

  kubernetes_version = var.kubernetes_version
  kms_key_arn        = aws_kms_key.platform.arn

  ecs_ami_id              = var.ecs_ami_id
  ecs_instance_type       = var.ecs_instance_type
  node_group_desired_size = var.node_group_desired_size
  node_group_min_size     = var.node_group_min_size
  node_group_max_size     = var.node_group_max_size
  ecs_desired_capacity    = var.ecs_desired_capacity
  ecs_min_size            = var.ecs_min_size
  ecs_max_size            = var.ecs_max_size

  tags = var.default_tags
}

# Azure Networking
module "azure_networking" {
  source = "../../../modules/networking/azure"

  environment          = var.environment_name
  location             = var.azure_location
  resource_group_name  = azurerm_resource_group.main.name
  vnet_cidr            = var.vnet_cidr
  public_subnet_cidrs  = var.azure_public_subnet_cidrs
  private_subnet_cidrs = var.azure_private_subnet_cidrs

  public_ingress_source_prefixes = var.azure_public_ingress_source_prefixes
  enable_nat_gateway             = true
  enable_private_link            = false

  tags = var.default_tags
}

module "azure_compute" {
  source = "../../../modules/compute/azure"

  environment         = var.environment_name
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.azure_networking.private_subnet_ids[0]

  kubernetes_version     = var.kubernetes_version
  admin_group_object_ids = var.azure_admin_group_object_ids

  allowed_ip_ranges = var.allowed_ip_ranges
  key_vault_key_id  = var.azure_key_vault_key_id

  tags = var.default_tags
}

# GCP Networking
module "gcp_networking" {
  source = "../../../modules/networking/gcp"

  environment          = var.environment_name
  project_id           = var.gcp_project_id
  region               = var.gcp_region
  public_subnet_cidrs  = var.gcp_public_subnet_cidrs
  private_subnet_cidrs = var.gcp_private_subnet_cidrs

  enable_vpc_sc    = false
  access_policy_id = var.gcp_access_policy_id
  project_number   = var.gcp_project_number

  # The database module owns the servicenetworking connection for this network.
  enable_private_service_connect = false
}

module "gcp_compute" {
  source = "../../../modules/compute/gcp"

  environment   = var.environment_name
  project_id    = var.gcp_project_id
  region        = var.gcp_region
  network_id    = module.gcp_networking.network_id
  subnetwork_id = module.gcp_networking.private_subnet_ids[0]

  master_ipv4_cidr_block   = var.gcp_master_cidr
  cluster_ipv4_cidr_block  = var.gcp_cluster_cidr
  services_ipv4_cidr_block = var.gcp_services_cidr

  network_usage_dataset_id = var.gcp_network_usage_dataset_id
  labels                   = local.gcp_labels
}

# AWS Database Resources
module "aws_database" {
  source = "../../../modules/database/aws"

  environment = var.environment_name
  vpc_id      = module.aws_networking.vpc_id
  subnet_ids  = module.aws_networking.private_subnet_ids
  allowed_security_groups = [
    module.aws_compute.ecs_security_group_id,
    module.aws_compute.eks_nodes_security_group_id,
  ]

  create_aurora_cluster = true
  database_name         = "govapp"
  master_username       = "admin"
  master_password       = var.aurora_master_password

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

  tags = var.default_tags
}

# Azure Database Resources
module "azure_database" {
  source = "../../../modules/database/azure"

  environment         = var.environment_name
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.azure_networking.private_subnet_ids[0]

  administrator_login    = "admin"
  administrator_password = var.azure_sql_password

  azure_ad_admin_username  = var.azure_ad_admin_username
  azure_ad_admin_object_id = var.azure_ad_admin_object_id

  private_dns_zone_id        = azurerm_private_dns_zone.sql.id
  cosmos_private_dns_zone_id = azurerm_private_dns_zone.cosmos.id
  log_analytics_workspace_id = module.azure_compute.log_analytics_workspace_id

  tags = var.default_tags
}

# GCP Database Resources
module "gcp_database" {
  source = "../../../modules/database/gcp"

  environment = var.environment_name
  project_id  = var.gcp_project_id
  region      = var.gcp_region
  network_id  = module.gcp_networking.network_id

  database_user     = "admin"
  database_password = var.gcp_db_password

  create_spanner           = true
  spanner_config           = "regional-us-east1"
  spanner_processing_units = 1000

  notification_channels = var.gcp_notification_channels

  labels = local.gcp_labels
}

# Cross-Cloud Network Connectivity (if required)
# Implementation depends on specific requirements and connectivity methods:
# AWS Direct Connect, Azure ExpressRoute, or GCP Cloud Interconnect.

# Outputs
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

output "aws_kms_key_arn" {
  value = aws_kms_key.platform.arn
}

output "azure_resource_group_name" {
  value = azurerm_resource_group.main.name
}

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
