mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "azurerm" {}
mock_provider "google" {}
mock_provider "tls" {}

run "production_stack_plans" {
  command = plan

  variables {
    environment_name = "test-southeast"
    aws_region       = "us-gov-east-1"
    ecs_ami_id       = "ami-0123456789abcdef0"

    azure_subscription_id        = "00000000-0000-0000-0000-000000000000"
    azure_tenant_id              = "00000000-0000-0000-0000-000000000000"
    azure_key_vault_key_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv/keys/key"
    azure_admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_ad_admin_username      = "admin@example.gov"
    azure_ad_admin_object_id     = "00000000-0000-0000-0000-000000000000"

    gcp_project_id     = "test-project"
    gcp_project_number = "123456789012"

    aurora_master_password = "test-only-password"
    azure_sql_password     = "test-only-password"
    gcp_db_password        = "test-only-password"
  }

  assert {
    condition     = length(module.aws_networking.private_subnet_ids) == 2
    error_message = "AWS networking should expose two private subnets."
  }

  assert {
    condition     = length(module.azure_networking.private_subnet_ids) == 2
    error_message = "Azure networking should expose two private subnets."
  }

  assert {
    condition     = length(module.gcp_networking.private_subnet_ids) == 2
    error_message = "GCP networking should expose two private subnets."
  }

  assert {
    condition     = output.azure_resource_group_name == "gov-prod-southeast-rg"
    error_message = "The Azure resource group output must resolve from configuration."
  }
}

run "rejects_insufficient_availability_zones" {
  command = plan

  variables {
    environment_name             = "test-southeast"
    aws_availability_zones       = ["us-gov-east-1a"]
    ecs_ami_id                   = "ami-0123456789abcdef0"
    azure_subscription_id        = "00000000-0000-0000-0000-000000000000"
    azure_tenant_id              = "00000000-0000-0000-0000-000000000000"
    azure_key_vault_key_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv/keys/key"
    azure_admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_ad_admin_username      = "admin@example.gov"
    azure_ad_admin_object_id     = "00000000-0000-0000-0000-000000000000"
    gcp_project_id               = "test-project"
    gcp_project_number           = "123456789012"
    aurora_master_password       = "test-only-password"
    azure_sql_password           = "test-only-password"
    gcp_db_password              = "test-only-password"
  }

  expect_failures = [
    var.aws_availability_zones,
  ]
}
