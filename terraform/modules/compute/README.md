# Multi-Cloud Compute Infrastructure

This directory contains Terraform modules for deploying and managing compute resources across AWS GovCloud, Azure Government, and Google Cloud Platform (GCP).

## Overview

The compute infrastructure is designed to support containerized workloads using:
- AWS: EKS (Kubernetes) and ECS (Container Service)
- Azure: AKS (Kubernetes)
- GCP: GKE (Kubernetes)

Each cloud provider's implementation includes:
- Container orchestration platforms
- Container registries
- Node pools/instance groups
- IAM/RBAC configurations
- Monitoring and logging
- Security controls

## Module Structure

```
compute/
├── aws/
│   ├── main.tf          # EKS and ECS cluster configurations
│   ├── iam.tf           # IAM roles and policies
│   └── templates/       # Instance configuration templates
├── azure/
│   └── main.tf          # AKS and ACR configurations
└── gcp/
    └── main.tf          # GKE and Artifact Registry configurations
```

## Features

### AWS (GovCloud)
- EKS cluster with managed node groups
- ECS cluster with auto-scaling groups
- Container registry access
- CloudWatch logging and monitoring
- KMS encryption
- VPC endpoint integration
- IAM roles and policies
- Security groups

### Azure (Government)
- AKS cluster with system and user node pools
- Azure Container Registry (Premium SKU)
- Azure Monitor integration
- Key Vault integration
- Network security groups
- Managed identities
- RBAC with Azure AD integration

### GCP
- GKE cluster with system and application node pools
- Artifact Registry
- Cloud Monitoring integration
- Workload Identity
- VPC Service Controls
- Binary Authorization
- Security controls

## Usage

### AWS Example
```hcl
module "aws_compute" {
  source = "../../../modules/compute/aws"

  environment         = "production"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  kubernetes_version = "1.27"
  
  # Additional configuration...
}
```

### Azure Example
```hcl
module "azure_compute" {
  source = "../../../modules/compute/azure"

  environment          = "production"
  location            = "usgovvirginia"
  resource_group_name = "my-resource-group"
  subnet_id           = module.networking.subnet_id
  
  # Additional configuration...
}
```

### GCP Example
```hcl
module "gcp_compute" {
  source = "../../../modules/compute/gcp"

  environment = "production"
  project_id  = "my-project"
  region      = "us-east4"
  network_id  = module.networking.network_id
  
  # Additional configuration...
}
```

## Security Considerations

1. Network Security
   - Private cluster endpoints
   - Network policies enabled
   - Restricted network access
   - Service mesh integration ready

2. Identity and Access Management
   - Least privilege principle
   - Managed identities/service accounts
   - RBAC integration
   - Multi-factor authentication support

3. Data Protection
   - Encryption at rest
   - Encryption in transit
   - Key management integration
   - Secure secrets management

4. Compliance
   - FedRAMP High baseline
   - NIST 800-53
   - DoD CC SRG
   - USCG security requirements

## Monitoring and Logging

Each cloud provider's implementation includes:
- Container insights
- Node monitoring
- Application metrics
- Audit logging
- Security logging
- Performance metrics
- Cost monitoring

## Maintenance

### Updates and Patches
1. Review release notes for each cloud provider
2. Test updates in lower environments
3. Use maintenance windows for updates
4. Follow change management procedures

### Backup and Recovery
1. Regular cluster backups
2. State file backups
3. Disaster recovery procedures
4. Cross-region replication (if required)

## Best Practices

1. Container Management
   - Use official base images
   - Implement image scanning
   - Enable vulnerability scanning
   - Implement resource limits

2. Scaling
   - Configure auto-scaling
   - Set appropriate thresholds
   - Monitor resource usage
   - Implement pod disruption budgets

3. Security
   - Regular security updates
   - Security scanning
   - Network isolation
   - Access control

4. Cost Management
   - Resource tagging
   - Cost allocation
   - Right-sizing
   - Spot/preemptible instances where appropriate

## Variables

Refer to each provider's module for specific variable definitions and requirements.

## Outputs

Each module provides outputs for:
- Cluster identifiers
- Endpoints
- Security group/firewall IDs
- Container registry information
- IAM/identity information

## Support

For issues or questions:
1. Review cloud provider documentation
2. Check terraform documentation
3. Consult USCG cloud team
4. Review security requirements
