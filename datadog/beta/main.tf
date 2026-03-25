# =============================================================================
# BETA CHANNEL — TERRAFORM CONFIGURATION
# =============================================================================
# Same pattern as alpha/main.tf. Key differences:
#   - S3 backend key: "datadog/beta/terraform.tfstate" (unique per channel)
#   - Secret paths: /beta/ instead of /alpha/
#
# This separation means changes to one channel CANNOT accidentally affect
# another channel's Terraform state. Each channel has its own state file,
# its own secrets, and its own config template.
# =============================================================================


# =============================================================================
# BLOCK 1: TERRAFORM SETTINGS
# =============================================================================
terraform {
  required_version = ">= 0.8, < 1"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  # UNIQUE backend key for beta channel — different from alpha
  backend "s3" {
    bucket = "acme-terraform-state"
    key    = "datadog/beta/terraform.tfstate"
    region = "us-east-1"
  }
}


# =============================================================================
# BLOCK 2: COMMON VARIABLES
# =============================================================================
module "common_vars" {
  source = "../common_vars"
}


# =============================================================================
# BLOCK 3: AWS PROVIDER
# =============================================================================
provider "aws" {
  region = module.common_vars.vars.region

  assume_role {
    role_arn = "arn:aws:iam::${module.common_vars.vars.aws_prd}:role/TerraformExecutionRole"
  }
}


# =============================================================================
# BLOCK 4: AWS SECRETS MANAGER — BETA-SPECIFIC SECRETS
# =============================================================================
# Note: /beta/ prefix — these are beta channel secrets, separate from /alpha/
# =============================================================================

data "aws_secretsmanager_secret_version" "external_api_url" {
  secret_id = "/beta/external_api_url"
}

data "aws_secretsmanager_secret_version" "inventory_api_token" {
  secret_id = "/beta/inventory_api_bearer_token"
}

data "aws_secretsmanager_secret_version" "legacy_apm_service_key" {
  secret_id = "/beta/legacy_apm_service_key"
}


# =============================================================================
# BLOCK 5: TEMPLATE FILE
# =============================================================================
data "template_file" "this" {
  template = file("config.yml.tmpl")

  vars = {
    external_api_url       = data.aws_secretsmanager_secret_version.external_api_url.secret_string
    inventory_api_token    = data.aws_secretsmanager_secret_version.inventory_api_token.secret_string
    legacy_apm_service_key = data.aws_secretsmanager_secret_version.legacy_apm_service_key.secret_string
  }
}


# =============================================================================
# BLOCK 6: DATADOG MODULE
# =============================================================================
module "synthetics_tests" {
  source = "git::https://github.com/example-org/terraform-datadog-module.git?ref=v2.0.0"

  synthetics_test_configs = data.template_file.this.rendered
}
