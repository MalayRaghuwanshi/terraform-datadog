# =============================================================================
# LOYALTY (LTY) CHANNEL — TERRAFORM CONFIGURATION
# =============================================================================
# Same pattern as ins/main.tf. Key differences:
#   - S3 backend key: "datadog/lty/terraform.tfstate" (unique per channel)
#   - Secret paths: /lty/ instead of /ins/
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

  # UNIQUE backend key for loyalty channel — different from ins
  backend "s3" {
    bucket = "loyalty-terraform-state"
    key    = "datadog/lty/terraform.tfstate"
    region = "ap-southeast-2"
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
# BLOCK 4: AWS SECRETS MANAGER — LTY-SPECIFIC SECRETS
# =============================================================================
# Note: /lty/ prefix — these are loyalty channel secrets, separate from /ins/
# =============================================================================

data "aws_secretsmanager_secret_version" "splunk_api_url" {
  secret_id = "/lty/splunk_api_url"
}

data "aws_secretsmanager_secret_version" "rewards_api_token" {
  secret_id = "/lty/rewards_api_bearer_token"
}

data "aws_secretsmanager_secret_version" "splunk_apm_service_key" {
  secret_id = "/lty/splunk_apm_service_key"
}


# =============================================================================
# BLOCK 5: TEMPLATE FILE
# =============================================================================
data "template_file" "this" {
  template = file("config.yml.tmpl")

  vars = {
    splunk_api_url       = data.aws_secretsmanager_secret_version.splunk_api_url.secret_string
    rewards_api_token    = data.aws_secretsmanager_secret_version.rewards_api_token.secret_string
    splunk_apm_service_key = data.aws_secretsmanager_secret_version.splunk_apm_service_key.secret_string
  }
}


# =============================================================================
# BLOCK 6: DATADOG MODULE
# =============================================================================
module "synthetics_tests" {
  source = "git::https://github.com/example-org/terraform-datadog-module.git?ref=v2.0.0"

  synthetics_test_configs = data.template_file.this.rendered
}
