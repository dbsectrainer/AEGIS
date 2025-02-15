# Azure Database Module

# Azure SQL Server
resource "azurerm_mssql_server" "main" {
  name                          = "${var.environment}-sql-server"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password

  azuread_administrator {
    login_username = var.azure_ad_admin_username
    object_id      = var.azure_ad_admin_object_id
  }

  identity {
    type = "SystemAssigned"
  }

  primary_user_assigned_identity_id = azurerm_user_assigned_identity.sql.id

  public_network_access_enabled = false

  tags = var.tags
}

# Azure SQL Database
resource "azurerm_mssql_database" "main" {
  name                = "${var.environment}-db"
  server_id          = azurerm_mssql_server.main.id
  collation          = "SQL_Latin1_General_CP1_CI_AS"
  sku_name           = var.sql_sku_name
  zone_redundant     = true
  
  short_term_retention_policy {
    retention_days = 7
  }

  long_term_retention_policy {
    weekly_retention  = "P4W"
    monthly_retention = "P12M"
    yearly_retention  = "P5Y"
    week_of_year     = 1
  }

  tags = var.tags
}

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "main" {
  name                = "${var.environment}-cosmos"
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_automatic_failover = true
  enable_multiple_write_locations = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
  }

  identity {
    type = "SystemAssigned"
  }

  network_acl_bypass_for_azure_services = true

  is_virtual_network_filter_enabled = true
  
  virtual_network_rule {
    id = var.subnet_id
  }

  tags = var.tags
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "${var.environment}-cosmos-db"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = var.cosmos_throughput
}

# Private Endpoints
resource "azurerm_private_endpoint" "sql" {
  name                = "${var.environment}-sql-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.environment}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.main.id
    is_manual_connection          = false
    subresource_names            = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "${var.environment}-cosmos-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.environment}-cosmos-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    is_manual_connection          = false
    subresource_names            = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}

# Managed Identity for SQL Server
resource "azurerm_user_assigned_identity" "sql" {
  name                = "${var.environment}-sql-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "sql" {
  name                       = "${var.environment}-sql-diag"
  target_resource_id        = azurerm_mssql_database.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "SQLInsights"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  log {
    category = "AutomaticTuning"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  log {
    category = "QueryStoreRuntimeStatistics"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  metric {
    category = "Basic"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  name                       = "${var.environment}-cosmos-diag"
  target_resource_id        = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "DataPlaneRequests"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  log {
    category = "QueryRuntimeStatistics"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }

  metric {
    category = "Requests"
    enabled  = true
    retention_policy {
      enabled = true
      days    = 30
    }
  }
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

variable "administrator_login" {
  description = "SQL Server administrator login"
  type        = string
}

variable "administrator_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "azure_ad_admin_username" {
  description = "Azure AD admin username"
  type        = string
}

variable "azure_ad_admin_object_id" {
  description = "Azure AD admin object ID"
  type        = string
}

variable "sql_sku_name" {
  description = "SQL Database SKU name"
  type        = string
  default     = "GP_Gen5_2"
}

variable "cosmos_throughput" {
  description = "Cosmos DB throughput (RU/s)"
  type        = number
  default     = 400
}

variable "subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "sql_server_id" {
  value = azurerm_mssql_server.main.id
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
}

output "sql_database_id" {
  value = azurerm_mssql_database.main.id
}

output "cosmos_account_id" {
  value = azurerm_cosmosdb_account.main.id
}

output "cosmos_account_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_database_id" {
  value = azurerm_cosmosdb_sql_database.main.id
}

output "sql_server_identity" {
  value = azurerm_user_assigned_identity.sql.id
}

output "sql_private_endpoint_ip" {
  value = azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address
}

output "cosmos_private_endpoint_ip" {
  value = azurerm_private_endpoint.cosmos.private_service_connection[0].private_ip_address
}
