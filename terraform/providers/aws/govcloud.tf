provider "aws" {
  # AWS GovCloud (US) Regions:
  # us-gov-east-1 (AWS GovCloud (US-East))
  # us-gov-west-1 (AWS GovCloud (US-West))
  region = var.aws_region

  # AWS GovCloud specific configurations
  alias = "govcloud"

  # Assume role if specified
  dynamic "assume_role" {
    for_each = var.assume_role_arn != "" ? [1] : []
    content {
      role_arn = var.assume_role_arn
    }
  }

  # Default tags for all AWS resources
  default_tags {
    tags = var.default_tags
  }
}

# AWS Provider Variables
variable "aws_region" {
  description = "AWS GovCloud region to deploy resources"
  type        = string
  default     = "us-gov-east-1"
}

variable "assume_role_arn" {
  description = "ARN of the role to assume for AWS operations"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags for all AWS resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "gov-cloud"
  }
}

# S3 Backend for State Management
terraform {
  backend "s3" {
    bucket         = "gov-terraform-state"
    key            = "govcloud/terraform.tfstate"
    region         = "us-gov-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for AWS partition (govcloud)
data "aws_partition" "current" {}

# Output AWS account information
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_partition" {
  value = data.aws_partition.current.partition
}
