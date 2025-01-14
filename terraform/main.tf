# USCG Multi-Cloud Infrastructure - Southeast Region Example

# Provider Configuration
provider "aws" {
  region = "us-gov-east-1"  # AWS GovCloud (US-East) for Southeast Region
  # Credentials should be provided via environment variables or IAM roles
}

provider "azurerm" {
  features {}
  environment = "usgovernment"  # Azure Government
  # Credentials should be provided via environment variables or managed identities
}

# AWS Resources
# VPC Configuration
resource "aws_vpc" "southeast_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "uscg-southeast-vpc"
    Environment = "production"
    Region      = "southeast"
  }
}

# Subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.southeast_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-gov-east-1a"

  tags = {
    Name = "uscg-southeast-private-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.southeast_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-gov-east-1b"

  tags = {
    Name = "uscg-southeast-private-2"
  }
}

# Security Groups
resource "aws_security_group" "vpc_endpoints" {
  name        = "vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.southeast_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.southeast_vpc.cidr_block]
  }
}

# VPC Endpoints for AWS Services
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.southeast_vpc.id
  service_name = "com.amazonaws.us-gov-east-1.s3"
  
  tags = {
    Name = "s3-endpoint"
  }
}

# Direct Connect Gateway
resource "aws_dx_gateway" "southeast" {
  name            = "uscg-southeast-dx-gateway"
  amazon_side_asn = "64512"
}

# Azure Resources
# Resource Group
resource "azurerm_resource_group" "southeast" {
  name     = "uscg-southeast-rg"
  location = "usgovvirginia"
}

# Virtual Network
resource "azurerm_virtual_network" "southeast" {
  name                = "uscg-southeast-vnet"
  resource_group_name = azurerm_resource_group.southeast.name
  location            = azurerm_resource_group.southeast.location
  address_space       = ["172.16.0.0/16"]
}

# Subnets
resource "azurerm_subnet" "private_subnet_1" {
  name                 = "private-subnet-1"
  resource_group_name  = azurerm_resource_group.southeast.name
  virtual_network_name = azurerm_virtual_network.southeast.name
  address_prefixes     = ["172.16.1.0/24"]
}

resource "azurerm_subnet" "private_subnet_2" {
  name                 = "private-subnet-2"
  resource_group_name  = azurerm_resource_group.southeast.name
  virtual_network_name = azurerm_virtual_network.southeast.name
  address_prefixes     = ["172.16.2.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "southeast" {
  name                = "uscg-southeast-nsg"
  location            = azurerm_resource_group.southeast.location
  resource_group_name = azurerm_resource_group.southeast.name

  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

# ExpressRoute Circuit
resource "azurerm_express_route_circuit" "southeast" {
  name                  = "uscg-southeast-expressroute"
  resource_group_name   = azurerm_resource_group.southeast.name
  location              = azurerm_resource_group.southeast.location
  service_provider_name = "Equinix"
  peering_location      = "Washington DC"
  bandwidth_in_mbps     = 1000

  sku {
    tier   = "Premium"
    family = "MeteredData"
  }
}

# Key Vault for Secrets Management
resource "azurerm_key_vault" "southeast" {
  name                       = "uscg-southeast-kv"
  location                   = azurerm_resource_group.southeast.location
  resource_group_name        = azurerm_resource_group.southeast.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                  = "premium"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
}

# Log Analytics Workspace for Monitoring
resource "azurerm_log_analytics_workspace" "southeast" {
  name                = "uscg-southeast-law"
  location            = azurerm_resource_group.southeast.location
  resource_group_name = azurerm_resource_group.southeast.name
  sku                = "PerGB2018"
  retention_in_days   = 90
}

# Storage Account for Logs and Backups
resource "azurerm_storage_account" "southeast" {
  name                     = "uscgsoutheastsa"
  resource_group_name      = azurerm_resource_group.southeast.name
  location                 = azurerm_resource_group.southeast.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version         = "TLS1_2"
  
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Output Values
output "aws_vpc_id" {
  value = aws_vpc.southeast_vpc.id
}

output "azure_vnet_id" {
  value = azurerm_virtual_network.southeast.id
}

output "dx_gateway_id" {
  value = aws_dx_gateway.southeast.id
}

output "expressroute_circuit_id" {
  value = azurerm_express_route_circuit.southeast.id
}
