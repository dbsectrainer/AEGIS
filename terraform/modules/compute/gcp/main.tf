# GCP Compute Module

# GKE Cluster
#tfsec:ignore:google-gke-enforce-pod-security-policy PSP was removed in GKE 1.25; configure Pod Security Admission on workload namespaces separately.
resource "google_container_cluster" "main" {
  name     = "${var.environment}-gke-cluster"
  location = var.region
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnetwork_id

  # Security posture scans for risks; it does not enforce Pod Security Admission.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable Network Policy
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Enable Private Cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Enable Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Enable Shielded Nodes
  release_channel {
    channel = "REGULAR"
  }

  # Master Authorized Networks
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Enable VPC Service Controls
  resource_usage_export_config {
    enable_network_egress_metering       = true
    enable_resource_consumption_metering = true
    bigquery_destination {
      dataset_id = var.network_usage_dataset_id
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T00:00:00Z"
      end_time   = "2024-01-02T00:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Enable Logging
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Enable Monitoring
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # IP Allocation Policy
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.cluster_ipv4_cidr_block
    services_ipv4_cidr_block = var.services_ipv4_cidr_block
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gcp_filestore_csi_driver_config {
      enabled = true
    }
    gke_backup_agent_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }
}

# Backup for GKE: daily at 00:00, retained 30 days
resource "google_gke_backup_backup_plan" "main" {
  name     = "${var.environment}-gke-backup-plan"
  cluster  = google_container_cluster.main.id
  location = var.region
  project  = var.project_id

  retention_policy {
    backup_retain_days = 30
  }

  backup_schedule {
    cron_schedule = "0 0 * * *"
  }

  backup_config {
    all_namespaces      = true
    include_volume_data = true
    include_secrets     = true
  }
}

# GKE Node Pools
resource "google_container_node_pool" "system" {
  name       = "${var.environment}-system-pool"
  location   = var.region
  cluster    = google_container_cluster.main.name
  project    = var.project_id
  node_count = var.system_node_count

  autoscaling {
    min_node_count = var.system_min_node_count
    max_node_count = var.system_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = var.system_machine_type
    disk_size_gb = var.system_disk_size
    disk_type    = "pd-ssd"

    labels = {
      environment = var.environment
      node-type   = "system"
    }

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      # The provider converts this boolean to the metadata string "true".
      disable-legacy-endpoints = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

resource "google_container_node_pool" "application" {
  name       = "${var.environment}-app-pool"
  location   = var.region
  cluster    = google_container_cluster.main.name
  project    = var.project_id
  node_count = var.app_node_count

  autoscaling {
    min_node_count = var.app_min_node_count
    max_node_count = var.app_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = var.app_machine_type
    disk_size_gb = var.app_disk_size
    disk_type    = "pd-ssd"

    labels = {
      environment = var.environment
      node-type   = "application"
    }

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      # The provider converts this boolean to the metadata string "true".
      disable-legacy-endpoints = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Service Account for GKE Nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.environment}-gke-nodes"
  display_name = "GKE Nodes Service Account"
  project      = var.project_id
}

# IAM Roles for GKE Node Service Account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Artifact Registry Repository
resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = "${var.environment}-container-repo"
  description   = "Container repository for ${var.environment}"
  format        = "DOCKER"
  project       = var.project_id

  docker_config {
    immutable_tags = true
  }
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

variable "subnetwork_id" {
  description = "VPC subnetwork ID"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation to use for the hosted master network"
  type        = string
}

variable "cluster_ipv4_cidr_block" {
  description = "The IP range in CIDR notation for the cluster pod IPs"
  type        = string
}

variable "services_ipv4_cidr_block" {
  description = "The IP range in CIDR notation for the cluster service IPs"
  type        = string
}

variable "master_authorized_networks" {
  description = "List of master authorized networks"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "network_usage_dataset_id" {
  description = "The ID of the BigQuery dataset for network usage export"
  type        = string
}

variable "system_node_count" {
  description = "Number of nodes in system node pool"
  type        = number
  default     = 3
}

variable "system_min_node_count" {
  description = "Minimum number of nodes in system node pool"
  type        = number
  default     = 1
}

variable "system_max_node_count" {
  description = "Maximum number of nodes in system node pool"
  type        = number
  default     = 5
}

variable "system_machine_type" {
  description = "Machine type for system nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "system_disk_size" {
  description = "Disk size for system nodes in GB"
  type        = number
  default     = 100
}

variable "app_node_count" {
  description = "Number of nodes in application node pool"
  type        = number
  default     = 2
}

variable "app_min_node_count" {
  description = "Minimum number of nodes in application node pool"
  type        = number
  default     = 1
}

variable "app_max_node_count" {
  description = "Maximum number of nodes in application node pool"
  type        = number
  default     = 10
}

variable "app_machine_type" {
  description = "Machine type for application nodes"
  type        = string
  default     = "e2-standard-8"
}

variable "app_disk_size" {
  description = "Disk size for application nodes in GB"
  type        = number
  default     = 100
}

# Outputs
output "cluster_id" {
  value = google_container_cluster.main.id
}

output "cluster_endpoint" {
  value = google_container_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  value = google_container_cluster.main.master_auth[0].cluster_ca_certificate
}

output "service_account_email" {
  value = google_service_account.gke_nodes.email
}

output "artifact_registry_id" {
  value = google_artifact_registry_repository.main.id
}

output "artifact_registry_location" {
  value = google_artifact_registry_repository.main.location
}
