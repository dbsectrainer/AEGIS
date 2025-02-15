# Multi-Cloud Database Infrastructure

This directory contains Terraform modules for deploying and managing database resources across AWS GovCloud, Azure Government, and Google Cloud Platform (GCP).

## Overview

The database infrastructure supports various managed database services:

### AWS (GovCloud)
- Amazon Aurora PostgreSQL (Serverless v2)
- Amazon DynamoDB
- Encrypted storage with KMS
- Enhanced monitoring
- Private subnet deployment
- Automated backups

### Azure (Government)
- Azure SQL Database
- Cosmos DB
- Private endpoints
- Managed identities
- Diagnostic settings
- Automated backups

### GCP
- Cloud SQL (PostgreSQL)
- Cloud Spanner
- Private service connections
- Monitoring alerts
- Automated backups

## Module Structure

```
database/
├── aws/
│   ├── main.tf          # Aurora and DynamoDB resources
│   └── iam.tf           # IAM roles and policies
├── azure/
│   └── main.tf          # Azure SQL and Cosmos DB resources
└── gcp/
    └── main.tf          # Cloud SQL and Spanner resources
```

## Features

### Common Features Across Providers
- Private networking
- Encryption at rest
- Automated backups
- Monitoring and alerting
- High availability
- Scalability options
- Performance insights

### AWS-Specific Features
- Serverless scaling
- Global tables (DynamoDB)
- Point-in-time recovery
- Cross-region replication
- IAM authentication

### Azure-Specific Features
- Active Directory integration
- Geo-replication
- Automatic tuning
- Long-term retention
- Threat detection

### GCP-Specific Features
- Regional availability
- Maintenance windows
- Query insights
- Automatic storage increases
- Cloud IAM integration

## Usage

### AWS Example
```hcl
module "aws_database" {
  source = "../../../modules/database/aws"

  environment          = "production"
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.private_subnet_ids
  allowed_security_groups = [module.compute.ecs_security_group_id]

  # Aurora Configuration
  create_aurora_cluster = true
  aurora_instance_count = 2
  database_name        = "myapp"
  master_username      = "admin"
  master_password      = var.database_password

  # DynamoDB Configuration
  dynamodb_tables = {
    users = {
      billing_mode = "PAY_PER_REQUEST"
      hash_key     = "user_id"
      attributes = [
        {
          name = "user_id"
          type = "S"
        }
      ]
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### Azure Example
```hcl
module "azure_database" {
  source = "../../../modules/database/azure"

  environment          = "production"
  location            = "usgovvirginia"
  resource_group_name = "my-resource-group"
  subnet_id           = module.networking.subnet_id

  administrator_login    = "admin"
  administrator_password = var.database_password
  
  azure_ad_admin_username  = "admin@domain.com"
  azure_ad_admin_object_id = "00000000-0000-0000-0000-000000000000"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### GCP Example
```hcl
module "gcp_database" {
  source = "../../../modules/database/gcp"

  environment = "production"
  project_id  = "my-project"
  region      = "us-east4"
  network_id  = module.networking.network_id

  database_user     = "admin"
  database_password = var.database_password
  sql_ip_range     = "10.0.0.0/16"

  # Optional Spanner Configuration
  create_spanner = true
  spanner_config = "regional-us-east1"

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
```

## Security Considerations

1. Network Security
   - Private endpoints/VPC endpoints
   - Network isolation
   - Encryption in transit
   - Firewall rules/security groups

2. Access Control
   - IAM/RBAC integration
   - Managed identities
   - Service accounts
   - Authentication methods

3. Data Protection
   - Encryption at rest
   - Backup retention
   - Point-in-time recovery
   - Audit logging

4. Compliance
   - FedRAMP High controls
   - NIST 800-53 requirements
   - DoD CC SRG alignment
   - Data residency requirements

## Monitoring and Maintenance

### Monitoring
- Performance metrics
- Query insights
- Resource utilization
- Error logging
- Alert policies

### Maintenance
- Automated backups
- Patch management
- Version upgrades
- Maintenance windows

## Best Practices

1. Security
   - Use private endpoints
   - Enable encryption
   - Implement least privilege
   - Regular security updates

2. Performance
   - Right-size instances
   - Monitor metrics
   - Implement caching
   - Query optimization

3. Reliability
   - Enable high availability
   - Configure backups
   - Test recovery procedures
   - Monitor replication

4. Cost Management
   - Use appropriate instance sizes
   - Enable auto-scaling
   - Monitor usage
   - Implement lifecycle policies

## Variables

Refer to each provider's module for specific variable definitions and requirements.

## Outputs

Each module provides outputs for:
- Database identifiers
- Connection endpoints
- Security group/firewall IDs
- Monitoring information

## Support

For issues or questions:
1. Review cloud provider documentation
2. Check terraform documentation
3. Consult USCG cloud team
4. Review security requirements
