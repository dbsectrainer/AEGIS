# USCG Multi-Cloud IAM Configuration

# AWS IAM Configuration
# Root Account Security
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers               = true
  require_symbols               = true
  password_reuse_prevention     = 24
  max_password_age             = 60
  allow_users_to_change_password = true
}

# Break Glass Emergency Access
resource "aws_iam_user" "break_glass" {
  name = "emergency-access"
  path = "/system/"

  tags = {
    Description = "Break Glass Emergency Access Account - Requires MFA"
    Type        = "Emergency"
  }
}

resource "aws_iam_group" "emergency_access" {
  name = "emergency-access"
  path = "/emergency/"
}

resource "aws_iam_group_membership" "emergency_team" {
  name  = "emergency-access-membership"
  users = [aws_iam_user.break_glass.name]
  group = aws_iam_group.emergency_access.name
}

# Security Audit Role
resource "aws_iam_role" "security_audit" {
  name = "security-audit-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "security_audit" {
  role       = aws_iam_role.security_audit.name
  policy_arn = "arn:aws-us-gov:iam::aws:policy/SecurityAudit"
}

# Service Accounts with Least Privilege
resource "aws_iam_role" "app_service" {
  name = "application-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Custom policy for least privilege
resource "aws_iam_role_policy" "app_service" {
  name = "application-service-policy"
  role = aws_iam_role.app_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws-us-gov:s3:::uscg-app-bucket",
          "arn:aws-us-gov:s3:::uscg-app-bucket/*"
        ]
      }
    ]
  })
}

# Azure IAM Configuration
# Custom RBAC Role
resource "azurerm_role_definition" "app_operator" {
  name        = "Application Operator"
  scope       = azurerm_resource_group.southeast.id
  description = "Custom role for application operators with least privilege"

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Resources/subscriptions/resourceGroups/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_resource_group.southeast.id
  ]
}

# Managed Identity for Applications
resource "azurerm_user_assigned_identity" "app_identity" {
  name                = "app-managed-identity"
  resource_group_name = azurerm_resource_group.southeast.name
  location            = azurerm_resource_group.southeast.location
}

# Key Vault Access Policy
resource "azurerm_key_vault_access_policy" "app_policy" {
  key_vault_id = azurerm_key_vault.southeast.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.app_identity.principal_id

  key_permissions = [
    "Get",
    "List"
  ]

  secret_permissions = [
    "Get",
    "List"
  ]

  certificate_permissions = [
    "Get",
    "List"
  ]
}

# Azure AD Security Configuration
resource "azuread_conditional_access_policy" "mfa_policy" {
  display_name = "MFA and PIV Enforcement"
  state        = "enabled"

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["all"]
    }

    users {
      included_users = ["all"]
    }
  }

  grant_controls {
    operator = "AND"
    built_in_controls = [
      "mfa",
      "compliantDevice",
      "domainJoinedDevice"
    ]
  }

  session_controls {
    sign_in_frequency = 1
    sign_in_frequency_period = "hours"
    persistent_browser_mode = "never"
  }
}

# Audit Logging Configuration
resource "azurerm_monitor_diagnostic_setting" "iam_audit" {
  name                       = "iam-audit-logs"
  target_resource_id         = azurerm_key_vault.southeast.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.southeast.id

  log {
    category = "AuditEvent"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 365
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 365
    }
  }
}

# Outputs
output "security_audit_role_arn" {
  value = aws_iam_role.security_audit.arn
}

output "app_service_role_arn" {
  value = aws_iam_role.app_service.arn
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.app_identity.id
}
