# Google Cloud Platform Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Use OAuth 2.0 access token if specified
  access_token = var.access_token

  # Use service account if specified
  dynamic "impersonate_service_account" {
    for_each = var.impersonate_service_account != "" ? [1] : []
    content {
      target_service_account = var.impersonate_service_account
    }
  }
}

# Enable required GCP APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudkms.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudasset.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudtrace.googleapis.com",
    "containerregistry.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

# GCP Provider Variables
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region to deploy resources"
  type        = string
  default     = "us-east4" # Virginia region for proximity to government agencies
}

variable "zone" {
  description = "GCP zone within the selected region"
  type        = string
  default     = "us-east4-a"
}

variable "access_token" {
  description = "OAuth 2.0 access token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "impersonate_service_account" {
  description = "Service account email to impersonate"
  type        = string
  default     = ""
}

variable "default_labels" {
  description = "Default labels for all GCP resources"
  type        = map(string)
  default = {
    environment = "production"
    managed_by  = "terraform"
    project     = "gov-cloud"
  }
}

# GCS Backend for State Management
terraform {
  backend "gcs" {
    bucket = "gov-terraform-state"
    prefix = "terraform/state"
  }
}

# Data sources for GCP configuration
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

# Organization policies for security
resource "google_project_organization_policy" "vm_external_ip_access" {
  project    = var.project_id
  constraint = "compute.vmExternalIpAccess"

  list_policy {
    deny {
      all = true
    }
  }
}

resource "google_project_organization_policy" "required_shielded_vm" {
  project    = var.project_id
  constraint = "compute.requireShieldedVm"

  boolean_policy {
    enforced = true
  }
}

resource "google_project_organization_policy" "restrict_vpc_peering" {
  project    = var.project_id
  constraint = "compute.restrictVpcPeering"

  list_policy {
    allow {
      values = ["under:organizations/${var.org_id}"]
    }
  }
}

# Outputs
output "project_number" {
  value = data.google_project.current.number
}

output "project_id" {
  value = data.google_project.current.project_id
}

output "enabled_apis" {
  value = [for api in google_project_service.required_apis : api.service]
}

# Additional Variables
variable "org_id" {
  description = "GCP Organization ID"
  type        = string
}

# VPC Service Controls (optional)
resource "google_access_context_manager_access_policy" "default" {
  count  = var.enable_vpc_service_controls ? 1 : 0
  parent = "organizations/${var.org_id}"
  title  = "GOV Default Access Policy"
}

variable "enable_vpc_service_controls" {
  description = "Enable VPC Service Controls"
  type        = bool
  default     = false
}

# Security Command Center Configuration (optional)
resource "google_project_service" "scc_api" {
  count   = var.enable_security_center ? 1 : 0
  project = var.project_id
  service = "securitycenter.googleapis.com"

  disable_on_destroy = false
}

variable "enable_security_center" {
  description = "Enable Security Command Center"
  type        = bool
  default     = false
}
