# Azure Networking Module

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.environment}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  dns_servers         = var.dns_servers

  tags = var.tags
}

# Subnets
resource "azurerm_subnet" "public" {
  count                = length(var.public_subnet_cidrs)
  name                 = "${var.environment}-public-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidrs[count.index]]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.ServiceBus"
  ]
}

resource "azurerm_subnet" "private" {
  count                = length(var.private_subnet_cidrs)
  name                 = "${var.environment}-private-subnet-${count.index + 1}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidrs[count.index]]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.ServiceBus"
  ]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Network Security Groups
resource "azurerm_network_security_group" "public" {
  name                = "${var.environment}-public-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.public_ingress_source_prefixes
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_security_group" "private" {
  name                = "${var.environment}-private-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "DenyInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = var.tags
}

# NSG Associations
resource "azurerm_subnet_network_security_group_association" "public" {
  count                     = length(var.public_subnet_cidrs)
  subnet_id                 = azurerm_subnet.public[count.index].id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  count                     = length(var.private_subnet_cidrs)
  subnet_id                 = azurerm_subnet.private[count.index].id
  network_security_group_id = azurerm_network_security_group.private.id
}

# Route Tables
resource "azurerm_route_table" "public" {
  name                = "${var.environment}-public-rt"
  location            = var.location
  resource_group_name = var.resource_group_name

  route {
    name           = "internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  tags = var.tags
}

resource "azurerm_route_table" "private" {
  name                = "${var.environment}-private-rt"
  location            = var.location
  resource_group_name = var.resource_group_name

  route {
    name           = "local-vnet"
    address_prefix = var.vnet_cidr
    next_hop_type  = "VnetLocal"
  }

  tags = var.tags
}

# Route Table Associations
resource "azurerm_subnet_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = azurerm_subnet.public[count.index].id
  route_table_id = azurerm_route_table.public.id
}

resource "azurerm_subnet_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = azurerm_subnet.private[count.index].id
  route_table_id = azurerm_route_table.private.id
}

# NAT Gateway (if enabled)
resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.environment}-nat-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.environment}-nat-gateway"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# Private Link Service (if enabled)
resource "azurerm_private_link_service" "main" {
  count               = var.enable_private_link ? 1 : 0
  name                = "${var.environment}-pls"
  location            = var.location
  resource_group_name = var.resource_group_name

  nat_ip_configuration {
    name      = "primary"
    subnet_id = azurerm_subnet.private[0].id
    primary   = true
  }

  load_balancer_frontend_ip_configuration_ids = var.load_balancer_frontend_ip_configuration_ids

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

variable "vnet_cidr" {
  description = "CIDR block for virtual network"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "dns_servers" {
  description = "Custom DNS servers"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = false
}

variable "enable_private_link" {
  description = "Enable Private Link Service"
  type        = bool
  default     = false
}

variable "load_balancer_frontend_ip_configuration_ids" {
  description = "List of Load Balancer Frontend IP Configuration IDs for Private Link Service"
  type        = list(string)
  default     = []
}

# Outputs
output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "public_subnet_ids" {
  value = azurerm_subnet.public[*].id
}

output "private_subnet_ids" {
  value = azurerm_subnet.private[*].id
}

output "nat_gateway_id" {
  value = var.enable_nat_gateway ? azurerm_nat_gateway.main[0].id : null
}

output "private_link_service_id" {
  value = var.enable_private_link ? azurerm_private_link_service.main[0].id : null
}

variable "public_ingress_source_prefixes" {
  description = "Source address prefixes or service tags allowed to reach the public NSG on 443 (e.g. AzureFrontDoor.Backend)"
  type        = list(string)
  default     = ["VirtualNetwork"]
}
