# GCP Database Module

# Cloud SQL Instance
resource "google_sql_database_instance" "main" {
  name                = "${var.environment}-sql-instance"
  database_version    = "POSTGRES_17"
  region              = var.region
  project             = var.project_id
  deletion_protection = true

  settings {
    tier              = var.instance_tier
    availability_type = "REGIONAL"
    disk_size         = var.disk_size
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      #tfsec:ignore:google-sql-encrypt-in-transit-data ssl_mode replaces the deprecated require_ssl
      ssl_mode           = "ENCRYPTED_ONLY"
      allocated_ip_range = var.sql_ip_range
    }

    database_flags {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 2 # 2 AM
      update_track = "stable"
    }
  }

  depends_on = [
    google_project_service.sql_admin,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Cloud SQL Database
resource "google_sql_database" "main" {
  name      = "${var.environment}-db"
  instance  = google_sql_database_instance.main.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Cloud SQL User
resource "google_sql_user" "main" {
  name     = var.database_user
  instance = google_sql_database_instance.main.name
  project  = var.project_id
  password = var.database_password
}

# Cloud Spanner Instance
resource "google_spanner_instance" "main" {
  count            = var.create_spanner ? 1 : 0
  name             = "${var.environment}-spanner"
  config           = var.spanner_config
  display_name     = "${var.environment} Spanner Instance"
  processing_units = var.spanner_processing_units
  project          = var.project_id

  labels = var.labels
}

# Cloud Spanner Database
resource "google_spanner_database" "main" {
  count                    = var.create_spanner ? 1 : 0
  instance                 = google_spanner_instance.main[0].name
  name                     = "${var.environment}-spanner-db"
  project                  = var.project_id
  version_retention_period = "7d"

  deletion_protection = true

  ddl = var.spanner_ddl_statements
}

# Private Service Connection
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.environment}-db-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Enable Required APIs
resource "google_project_service" "sql_admin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "spanner" {
  count   = var.create_spanner ? 1 : 0
  project = var.project_id
  service = "spanner.googleapis.com"

  disable_on_destroy = false
}

# Monitoring
resource "google_monitoring_alert_policy" "database_cpu" {
  display_name = "${var.environment}-database-cpu-alert"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "High CPU Usage"
    condition_threshold {
      filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      trigger {
        count = 1
      }
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
}

resource "google_monitoring_alert_policy" "spanner_cpu" {
  count        = var.create_spanner ? 1 : 0
  display_name = "${var.environment}-spanner-cpu-alert"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "High CPU Usage"
    condition_threshold {
      filter          = "metric.type=\"spanner.googleapis.com/instance/cpu/utilization\" resource.type=\"spanner_instance\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      trigger {
        count = 1
      }
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "sql_ip_range" {
  description = "IP range for Cloud SQL"
  type        = string
}

variable "instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 100
}

variable "database_user" {
  description = "Database user name"
  type        = string
}

variable "database_password" {
  description = "Database user password"
  type        = string
  sensitive   = true
}

variable "create_spanner" {
  description = "Whether to create Cloud Spanner resources"
  type        = bool
  default     = false
}

variable "spanner_config" {
  description = "Cloud Spanner configuration"
  type        = string
  default     = "regional-us-east1"
}

variable "spanner_processing_units" {
  description = "Cloud Spanner processing units"
  type        = number
  default     = 1000
}

variable "spanner_ddl_statements" {
  description = "Cloud Spanner DDL statements"
  type        = list(string)
  default     = []
}

variable "notification_channels" {
  description = "Monitoring notification channel IDs"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "sql_instance_name" {
  value = google_sql_database_instance.main.name
}

output "sql_instance_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "sql_database_name" {
  value = google_sql_database.main.name
}

output "sql_private_ip_address" {
  value = google_sql_database_instance.main.private_ip_address
}

output "spanner_instance_id" {
  value = var.create_spanner ? google_spanner_instance.main[0].id : null
}

output "spanner_database_id" {
  value = var.create_spanner ? google_spanner_database.main[0].id : null
}
