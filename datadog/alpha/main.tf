# =============================================================================
# ALPHA CHANNEL — TERRAFORM CONFIGURATION
# =============================================================================
# This file wires together:
#   1. Terraform settings and providers
#   2. Shared variables from common_vars
#   3. Secrets from AWS Secrets Manager
#   4. The config template (config.yml.tmpl) with secrets injected
#   5. The Datadog module that creates the actual resources
# =============================================================================


# =============================================================================
# BLOCK 1: TERRAFORM SETTINGS
# =============================================================================
# This block configures Terraform itself — what version to use, which providers
# to download, and WHERE to store the state file.
#
# BACKEND KEY UNIQUENESS:
# The backend key "datadog/alpha/terraform.tfstate" MUST be unique per channel.
# If two channels used the same key, they would overwrite each other's state
# and DESTROY each other's resources. The alpha channel uses datadog/alpha/...,
# the beta channel uses datadog/beta/..., etc.
# =============================================================================
terraform {
  required_version = ">= 0.8, < 1"

  required_providers {
    # Datadog provider — manages synthetics, monitors, dashboards, etc.
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
    # AWS provider — needed to read secrets from AWS Secrets Manager
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  # Remote state storage in S3
  # The state file tracks every resource Terraform manages.
  # Storing it in S3 (not locally) means:
  #   - The CI/CD pipeline can access it
  #   - Multiple team members can collaborate
  #   - State is backed up and versioned by S3
  backend "s3" {
    bucket = "acme-terraform-state"
    key    = "datadog/alpha/terraform.tfstate"
    region = "us-east-1"
  }
}


# =============================================================================
# BLOCK 2: COMMON VARIABLES MODULE
# =============================================================================
# Pulls in shared variables (AWS account IDs, region, Datadog site) so we
# don't hardcode these values in every channel's files.
# If an account ID changes, we update common_vars once — not every channel.
# =============================================================================
module "common_vars" {
  source = "../common_vars"
}


# =============================================================================
# BLOCK 3: AWS PROVIDER
# =============================================================================
# We need the AWS provider to read secrets from AWS Secrets Manager.
# The assume_role block lets Terraform authenticate to the correct AWS account
# by assuming an IAM role — this is how CI/CD pipelines and cross-account
# access work in AWS.
# =============================================================================
provider "aws" {
  region = module.common_vars.vars.region

  assume_role {
    role_arn = "arn:aws:iam::${module.common_vars.vars.aws_prd}:role/TerraformExecutionRole"
  }
}


# =============================================================================
# BLOCK 4: AWS SECRETS MANAGER — READ-ONLY LOOKUPS
# =============================================================================
# These are READ-ONLY lookups. Terraform does NOT manage these secrets — it
# just reads them so it can inject them into the config template.
#
# The secrets are stored and managed in AWS Secrets Manager, not in this repo.
# This means:
#   - Secrets are never in Git (safe to commit this file)
#   - Secrets can be rotated in AWS without changing Terraform code
#   - Access to secrets is controlled by IAM policies
# =============================================================================

# The external API URL — contains authentication credentials in the URL itself
data "aws_secretsmanager_secret_version" "external_api_url" {
  secret_id = "/alpha/external_api_url"
}

# Bearer token for the Checkout API — used in synthetic checks
data "aws_secretsmanager_secret_version" "checkout_api_token" {
  secret_id = "/alpha/checkout_api_bearer_token"
}

# Legacy APM service key — used to authenticate with the legacy APM service
data "aws_secretsmanager_secret_version" "legacy_apm_service_key" {
  secret_id = "/alpha/legacy_apm_service_key"
}


# =============================================================================
# BLOCK 5: TEMPLATE FILE — BRIDGE BETWEEN CONFIG AND SECRETS
# =============================================================================
# This is the bridge between the config file and the secrets.
# The template (config.yml.tmpl) is read from disk, and every ${variable}
# placeholder is replaced with the real value from AWS Secrets Manager.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ IMPORTANT: TWO DIFFERENT TEMPLATE SYNTAXES IN THE SAME FILE            │
# │                                                                         │
# │ ${external_api_url}  = TERRAFORM syntax, replaced at plan/apply time   │
# │                        Terraform reads the secret from AWS and          │
# │                        substitutes the real value into the template.    │
# │                        ${} NEVER appears in the final rendered output.  │
# │                        Datadog never sees these placeholders.           │
# │                                                                         │
# │ {{#is_alert}}        = DATADOG syntax, used when an alert fires        │
# │                        These ARE in the rendered output and Datadog     │
# │                        interprets them when the monitor triggers.       │
# │                        {{value}} shows the actual metric value.         │
# │                        {{threshold}} shows the configured threshold.    │
# │                                                                         │
# │ These are completely different systems — don't confuse them.            │
# └─────────────────────────────────────────────────────────────────────────┘
# =============================================================================
data "template_file" "this" {
  template = file("config.yml.tmpl")

  vars = {
    external_api_url       = data.aws_secretsmanager_secret_version.external_api_url.secret_string
    checkout_api_token     = data.aws_secretsmanager_secret_version.checkout_api_token.secret_string
    legacy_apm_service_key = data.aws_secretsmanager_secret_version.legacy_apm_service_key.secret_string
  }
}


# =============================================================================
# BLOCK 6: DATADOG MODULE — CREATES THE ACTUAL RESOURCES
# =============================================================================
# .rendered is the final YAML string AFTER all ${} substitutions have been
# made. This string contains real secret values (in memory only — never
# written to disk or committed to Git).
#
# The module reads this rendered YAML and creates the Datadog resources:
#   - datadog_synthetics_test for each synthetic block
#   - datadog_monitor for each monitor block
# =============================================================================
module "synthetics_tests" {
  source = "git::https://github.com/example-org/terraform-datadog-module.git?ref=v2.0.0"

  synthetics_test_configs = data.template_file.this.rendered
}
