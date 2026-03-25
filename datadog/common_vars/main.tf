# =============================================================================
# COMMON VARIABLES MODULE
# =============================================================================
# This is a shared module — every channel (ins, lty, etc.) calls this module
# to get common values rather than hardcoding them in every channel's files.
#
# WHY: If the AWS account ID changes or we move to a different Datadog site,
# we update it HERE once and every channel picks up the change automatically.
# Without this, we would need to find and update every hardcoded value across
# every channel — error-prone and dangerous.
# =============================================================================

locals {
  # AWS region for all resources
  region = "ap-southeast-2"

  # AWS account IDs
  # prd  = Production account — where live monitoring resources are deployed
  # nprd = Non-production account — for staging/testing Terraform changes
  aws_prd  = "111111111111"
  aws_nprd = "222222222222"

  # Datadog site — determines which Datadog data center we connect to
  # datadoghq.com = US1 (default)
  # Other options: datadoghq.eu, us3.datadoghq.com, us5.datadoghq.com
  datadog_site = "datadoghq.com"
}

# =============================================================================
# OUTPUT: Expose the locals so other modules can reference them
# Usage in channel main.tf:
#   module.common_vars.vars.region
#   module.common_vars.vars.aws_prd
# =============================================================================
output "vars" {
  value = local
}
