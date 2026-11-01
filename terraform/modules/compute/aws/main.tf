# AWS Compute Module

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  deletion_protection = true

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = var.tags
}

# Launch template attaches the module-managed node security group to managed nodes.
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.environment}-eks-nodes-"

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tags = var.tags
}

# EKS Node Groups
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  update_config {
    max_unavailable = 1
  }

  labels = merge(var.tags, {
    "node.type" = "managed"
  })

  tags = var.tags
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs.name
      }
    }
  }

  tags = var.tags
}

# ECS Capacity Providers
resource "aws_ecs_capacity_provider" "main" {
  name = "${var.environment}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 100
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = var.tags
}

# Attach the capacity provider to the cluster so ECS can place tasks.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.main.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 1
    base              = 0
  }
}

# Auto Scaling Group for ECS
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.environment}-ecs-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = var.target_group_arns
  health_check_type   = "ELB"
  min_size            = var.ecs_min_size
  max_size            = var.ecs_max_size
  desired_capacity    = var.ecs_desired_capacity

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Launch Template for ECS
resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.environment}-ecs-lt"
  image_id      = var.ecs_ami_id
  instance_type = var.ecs_instance_type

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ecs.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs.name
  }

  user_data = base64encode(templatefile("${path.module}/templates/ecs-userdata.sh", {
    cluster_name = aws_ecs_cluster.main.name
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.ecs_volume_size
      encrypted   = true
      kms_key_id  = var.kms_key_arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tags = var.tags
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.environment}-eks-cluster-sg"
  description = "EKS control-plane security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Control-plane API access from the cluster security group"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress to private subnets and interface endpoints"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, {
    "Name" = "${var.environment}-eks-cluster-sg"
  })
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.environment}-eks-nodes-sg"
  description = "EKS worker-node security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Control-plane and node traffic"
    from_port       = 0
    to_port         = 65535
    protocol        = "-1"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress to private subnets and interface endpoints"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, {
    "Name" = "${var.environment}-eks-nodes-sg"
  })
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.environment}-ecs-sg"
  description = "ECS container-instance security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Traffic from private subnets"
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress to private subnets and interface endpoints"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, {
    "Name" = "${var.environment}-ecs-sg"
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.environment}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${var.environment}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
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

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_instance_types" {
  description = "List of instance types for the worker nodes"
  type        = list(string)
  default     = ["m5.large"]
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
}

variable "ecs_min_size" {
  description = "Minimum number of ECS instances"
  type        = number
  default     = 1
}

variable "ecs_max_size" {
  description = "Maximum number of ECS instances"
  type        = number
  default     = 4
}

variable "ecs_desired_capacity" {
  description = "Desired number of ECS instances"
  type        = number
  default     = 2
}

variable "ecs_ami_id" {
  description = "AMI ID for ECS instances"
  type        = string
}

variable "ecs_instance_type" {
  description = "Instance type for ECS instances"
  type        = string
  default     = "m5.large"
}

variable "ecs_volume_size" {
  description = "Volume size for ECS instances"
  type        = number
  default     = 30
}

variable "target_group_arns" {
  description = "List of target group ARNs for ASG"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "eks_cluster_id" {
  value = aws_eks_cluster.main.id
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "eks_cluster_security_group_id" {
  value = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  value = aws_security_group.eks_nodes.id
}

output "ecs_cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}
