# Local emulation fixture for AWS Terraform patterns.
#
# This fixture runs against LocalStack and verifies real AWS provider CRUD for
# services the community emulator supports (S3, DynamoDB, SQS, SNS, IAM, KMS,
# CloudWatch Logs, EC2 networking). It is not a deployment target and does not
# emulate GovCloud, EKS, ECS, or RDS.
#
# Start LocalStack with tests/localstack/run-localstack-tests.sh, or point
# localstack_endpoint at an already-running instance.

terraform {
  required_version = ">= 1.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    cloudwatch = var.localstack_endpoint
    dynamodb   = var.localstack_endpoint
    ec2        = var.localstack_endpoint
    iam        = var.localstack_endpoint
    kms        = var.localstack_endpoint
    logs       = var.localstack_endpoint
    s3         = var.localstack_endpoint
    sns        = var.localstack_endpoint
    sqs        = var.localstack_endpoint
    sts        = var.localstack_endpoint
  }
}

resource "aws_vpc" "local" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "aegis-local-vpc" }
}

resource "aws_subnet" "local" {
  count             = 2
  vpc_id            = aws_vpc.local.id
  cidr_block        = "10.42.${count.index + 1}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"

  tags = { Name = "aegis-local-subnet-${count.index + 1}" }
}

resource "aws_security_group" "app" {
  name        = "aegis-local-app"
  description = "Local emulation application security group"
  vpc_id      = aws_vpc.local.id

  ingress {
    description = "Application traffic within the local VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.local.cidr_block]
  }

  tags = { Name = "aegis-local-app" }
}

resource "aws_s3_bucket" "evidence" {
  bucket        = "aegis-local-evidence"
  force_destroy = true
  tags          = { Purpose = "local-emulation" }
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket                  = aws_s3_bucket.evidence.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sqs_queue" "events" {
  name                       = "aegis-local-events"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
  tags                       = { Purpose = "local-emulation" }
}

resource "aws_sns_topic" "alerts" {
  name = "aegis-local-alerts"
  tags = { Purpose = "local-emulation" }
}

resource "aws_sns_topic_subscription" "events" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.events.arn
}

resource "aws_kms_key" "local" {
  description         = "AEGIS local emulation key"
  enable_key_rotation = true
  tags                = { Purpose = "local-emulation" }
}

resource "aws_kms_alias" "local" {
  name          = "alias/aegis-local"
  target_key_id = aws_kms_key.local.key_id
}

resource "aws_cloudwatch_log_group" "local" {
  name              = "/aegis/local/application"
  retention_in_days = 30
  tags              = { Purpose = "local-emulation" }
}

resource "aws_dynamodb_table" "audit" {
  name         = "aegis-local-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  range_key    = "timestamp"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = { Purpose = "local-emulation" }
}

resource "aws_iam_role" "runtime" {
  name = "aegis-local-runtime"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Purpose = "local-emulation" }
}

resource "aws_iam_role_policy" "runtime" {
  name = "aegis-local-runtime-policy"
  role = aws_iam_role.runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "dynamodb:GetItem"]
      Resource = [aws_s3_bucket.evidence.arn, aws_dynamodb_table.audit.arn]
    }]
  })
}

output "s3_bucket" {
  value = aws_s3_bucket.evidence.id
}

output "sqs_queue_url" {
  value = aws_sqs_queue.events.url
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "kms_alias" {
  value = aws_kms_alias.local.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.local.name
}

output "audit_table" {
  value = aws_dynamodb_table.audit.name
}

output "vpc_id" {
  value = aws_vpc.local.id
}

output "runtime_role" {
  value = aws_iam_role.runtime.name
}
