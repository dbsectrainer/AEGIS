# AWS Database Module

# KMS Key for Database Encryption
resource "aws_kms_key" "database" {
  description             = "KMS key for database encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = var.tags
}

resource "aws_kms_alias" "database" {
  name          = "alias/${var.environment}-database"
  target_key_id = aws_kms_key.database.key_id
}

# RDS Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "main" {
  count                        = var.create_aurora_cluster ? 1 : 0
  cluster_identifier           = "${var.environment}-aurora-cluster"
  engine                       = "aurora-postgresql"
  engine_version               = var.aurora_engine_version
  database_name                = var.database_name
  master_username              = var.master_username
  master_password              = var.master_password
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  db_subnet_group_name         = aws_db_subnet_group.main.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  storage_encrypted            = true
  kms_key_id                   = aws_kms_key.database.arn
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.environment}-aurora-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_capacity
    max_capacity = var.aurora_max_capacity
  }

  tags = var.tags
}

resource "aws_rds_cluster_instance" "main" {
  count              = var.create_aurora_cluster ? var.aurora_instance_count : 0
  identifier         = "${var.environment}-aurora-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main[0].id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.main[0].engine
  engine_version     = aws_rds_cluster.main[0].engine_version

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.database.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  tags = var.tags
}

# DynamoDB Tables
resource "aws_dynamodb_table" "main" {
  for_each = var.dynamodb_tables

  name           = "${var.environment}-${each.key}"
  billing_mode   = each.value.billing_mode
  read_capacity  = each.value.billing_mode == "PROVISIONED" ? each.value.read_capacity : null
  write_capacity = each.value.billing_mode == "PROVISIONED" ? each.value.write_capacity : null
  hash_key       = each.value.hash_key
  range_key      = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
      read_capacity   = each.value.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity  = each.value.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.database.arn
  }

  tags = var.tags
}

# Security Group for Databases
resource "aws_security_group" "database" {
  name_prefix = "${var.environment}-database-"
  vpc_id      = var.vpc_id
  description = "Security group for database resources"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
    description     = "Allow PostgreSQL access from application tier"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = var.allowed_security_groups
    description     = "Allow outbound traffic to application tier only"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-database-sg"
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.environment}-db-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group for database resources"

  tags = var.tags
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count               = var.create_aurora_cluster ? var.aurora_instance_count : 0
  alarm_name          = "${var.environment}-aurora-cpu-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.main[count.index].id
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  for_each = var.dynamodb_tables

  alarm_name          = "${var.environment}-${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttled requests"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.main[each.key].name
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the database resources"
  type        = list(string)
}

variable "allowed_security_groups" {
  description = "List of security group IDs allowed to access the databases"
  type        = list(string)
}

variable "create_aurora_cluster" {
  description = "Whether to create an Aurora cluster"
  type        = bool
  default     = true
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.5"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances"
  type        = number
  default     = 2
}

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.serverless"
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora capacity units"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora capacity units"
  type        = number
  default     = 16
}

variable "database_name" {
  description = "Name of the initial database"
  type        = string
}

variable "master_username" {
  description = "Master username for the database cluster"
  type        = string
}

variable "master_password" {
  description = "Master password for the database cluster"
  type        = string
  sensitive   = true
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 35
}

variable "preferred_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "dynamodb_tables" {
  description = "Map of DynamoDB table configurations"
  type = map(object({
    billing_mode   = string
    read_capacity  = optional(number)
    write_capacity = optional(number)
    hash_key       = string
    range_key      = optional(string)
    attributes = list(object({
      name = string
      type = string
    }))
    global_secondary_indexes = optional(list(object({
      name            = string
      hash_key        = string
      range_key       = optional(string)
      projection_type = string
      read_capacity   = optional(number)
      write_capacity  = optional(number)
    })), [])
  }))
  default = {}
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "aurora_cluster_endpoint" {
  value = var.create_aurora_cluster ? aws_rds_cluster.main[0].endpoint : null
}

output "aurora_cluster_reader_endpoint" {
  value = var.create_aurora_cluster ? aws_rds_cluster.main[0].reader_endpoint : null
}

output "aurora_cluster_id" {
  value = var.create_aurora_cluster ? aws_rds_cluster.main[0].id : null
}

output "dynamodb_table_arns" {
  value = { for k, v in aws_dynamodb_table.main : k => v.arn }
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}

output "kms_key_arn" {
  value = aws_kms_key.database.arn
}
