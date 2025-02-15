# GCP Project Configuration
gcp_project_id       = "gov-prod-southeast"
gcp_project_number   = "123456789012" # Replace with actual project number
gcp_access_policy_id = "987654321"    # Replace with actual access policy ID

# AWS Configuration
aws_region          = "us-gov-east-1"
aws_kms_key_arn     = "arn:aws-us-gov:kms:us-gov-east-1:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd5678"
aws_ssh_key_name    = "gov-prod-southeast"
aws_ecs_ami_id      = "ami-123456789" # Replace with actual ECS-optimized AMI ID

# Azure Configuration
azure_location           = "usgovvirginia"
azure_resource_group    = "gov-prod-southeast-rg"
azure_key_vault_key_id  = "/subscriptions/12345678-1234-5678-1234-567812345678/resourceGroups/gov-prod-southeast-rg/providers/Microsoft.KeyVault/vaults/gov-prod-kv/keys/container-registry"
azure_admin_group_ids   = ["12345678-1234-5678-1234-567812345678"] # Replace with actual Azure AD group IDs

# Kubernetes Configuration
kubernetes_version     = "1.27"

# Network Configuration
vpc_cidr              = "10.0.0.0/16"
vnet_cidr             = "172.16.0.0/16"
gcp_master_cidr       = "172.16.0.0/28"
gcp_cluster_cidr      = "10.4.0.0/16"
gcp_services_cidr     = "10.5.0.0/16"

# Security Configuration
allowed_ip_ranges     = "10.0.0.0/8"

# Resource Sizing
system_node_count     = 3
app_node_count        = 2
ecs_instance_count    = 2

# Database Configuration
aurora_master_password = "REPLACE_WITH_SECURE_PASSWORD"  # Replace with actual password
azure_sql_password     = "REPLACE_WITH_SECURE_PASSWORD"  # Replace with actual password
gcp_db_password       = "REPLACE_WITH_SECURE_PASSWORD"  # Replace with actual password

# Azure AD Configuration
azure_ad_admin_username  = "admin@gov.gov"
azure_ad_admin_object_id = "12345678-1234-5678-1234-567812345678"  # Replace with actual Object ID

# Azure Resource IDs
azure_private_dns_zone_id = "/subscriptions/12345678-1234-5678-1234-567812345678/resourceGroups/gov-prod-southeast-rg/providers/Microsoft.Network/privateDnsZones/privatelink.database.usgovcloudapi.net"
azure_log_analytics_workspace_id = "/subscriptions/12345678-1234-5678-1234-567812345678/resourceGroups/gov-prod-southeast-rg/providers/Microsoft.OperationalInsights/workspaces/gov-prod-law"

# GCP Monitoring
gcp_notification_channels = [
  "projects/gov-prod-southeast/notificationChannels/12345678901234567890"
]

# Tags
default_tags = {
  Environment = "production"
  Region      = "southeast"
  ManagedBy   = "terraform"
  Project     = "gov-cloud"
}
