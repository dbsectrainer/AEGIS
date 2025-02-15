# GCP Networking Module

# VPC Network
resource "google_compute_network" "main" {
  name                            = "${var.environment}-vpc"
  auto_create_subnetworks        = false
  routing_mode                   = "GLOBAL"
  delete_default_routes_on_create = true

  depends_on = [
    google_project_service.compute_api
  ]
}

# Enable required APIs
resource "google_project_service" "compute_api" {
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

# Subnets
resource "google_compute_subnetwork" "public" {
  count         = length(var.public_subnet_cidrs)
  name          = "${var.environment}-public-subnet-${count.index + 1}"
  ip_cidr_range = var.public_subnet_cidrs[count.index]
  region        = var.region
  network       = google_compute_network.main.id

  # Enable flow logs
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }

  # Enable private Google access
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "private" {
  count         = length(var.private_subnet_cidrs)
  name          = "${var.environment}-private-subnet-${count.index + 1}"
  ip_cidr_range = var.private_subnet_cidrs[count.index]
  region        = var.region
  network       = google_compute_network.main.id

  # Enable flow logs
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }

  # Enable private Google access
  private_ip_google_access = true
}

# Cloud Router for NAT Gateway
resource "google_compute_router" "nat_router" {
  name    = "${var.environment}-nat-router"
  network = google_compute_network.main.id
  region  = var.region

  bgp {
    asn = 64514
  }
}

# Cloud NAT
resource "google_compute_router_nat" "main" {
  name                               = "${var.environment}-nat"
  router                            = google_compute_router.nat_router.name
  region                            = var.region
  nat_ip_allocate_option           = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.main.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = concat(var.public_subnet_cidrs, var.private_subnet_cidrs)
}

resource "google_compute_firewall" "allow_https" {
  name    = "${var.environment}-allow-https"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["https"]
}

# VPC Service Controls (if enabled)
resource "google_access_context_manager_service_perimeter" "regular" {
  count          = var.enable_vpc_sc ? 1 : 0
  parent         = "accessPolicies/${var.access_policy_id}"
  name           = "accessPolicies/${var.access_policy_id}/servicePerimeters/${var.environment}-perimeter"
  title          = "${var.environment}-perimeter"
  perimeter_type = "PERIMETER_TYPE_REGULAR"

  status {
    restricted_services = [
      "compute.googleapis.com",
      "storage.googleapis.com",
      "bigquery.googleapis.com"
    ]

    resources = ["projects/${var.project_number}"]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services  = ["compute.googleapis.com"]
    }

    access_levels = var.access_level_names
  }
}

# Private Service Connect
resource "google_compute_global_address" "private_service_connect" {
  count         = var.enable_private_service_connect ? 1 : 0
  name          = "${var.environment}-psc-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_service_connect" {
  count                   = var.enable_private_service_connect ? 1 : 0
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_connect[0].name]
}

# Routes
resource "google_compute_route" "egress_internet" {
  name             = "${var.environment}-egress-internet"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.main.id
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
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

variable "enable_vpc_sc" {
  description = "Enable VPC Service Controls"
  type        = bool
  default     = false
}

variable "access_policy_id" {
  description = "Access Policy ID for VPC Service Controls"
  type        = string
  default     = ""
}

variable "project_number" {
  description = "GCP project number"
  type        = string
}

variable "access_level_names" {
  description = "List of Access Level names for VPC Service Controls"
  type        = list(string)
  default     = []
}

variable "enable_private_service_connect" {
  description = "Enable Private Service Connect"
  type        = bool
  default     = false
}

# Outputs
output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "public_subnet_ids" {
  value = google_compute_subnetwork.public[*].id
}

output "private_subnet_ids" {
  value = google_compute_subnetwork.private[*].id
}

output "nat_router_id" {
  value = google_compute_router.nat_router.id
}

output "cloud_nat_id" {
  value = google_compute_router_nat.main.id
}
