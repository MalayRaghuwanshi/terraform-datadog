# Terraform-Datadog Monitoring

Manages all Datadog monitoring resources (synthetics and monitors) via Terraform, stored in GitHub, and deployed through CI/CD.

## Migration Context

This repository represents the migration from **Splunk APM** to **Datadog**. All monitoring that previously lived in Splunk — synthetics (uptime checks) and detectors (metric alerts) — is now defined as code here and managed through Pull Requests.

| Splunk APM Concept | Datadog Equivalent | Where in this repo |
|-|-|-|
| Synthetic (uptime check) | `datadog_synthetics_test` | `config.yml.tmpl` |
| Detector (error rate) | `datadog_monitor` (metric alert) | `config.yml.tmpl` |
| Detector (latency) | `datadog_monitor` (metric alert) | `config.yml.tmpl` |
| Detector (service down) | `datadog_monitor` (service check) | `config.yml.tmpl` |
| Notification routing | `message` block with `@pagerduty` / `@slack` | `config.yml.tmpl` |

## Folder Structure

```
terraform-datadog/
├── .gitignore
├── README.md
├── .github/
│   └── workflows/
│       └── terraform.yml          # CI/CD: plan on PR, apply on merge
└── datadog/
    ├── common_vars/
    │   └── main.tf                # Shared vars used by every channel
    ├── ins/                       # Insurance channel
    │   ├── main.tf                # Terraform wiring + secret injection
    │   └── config.yml.tmpl        # Synthetics + monitors for ins
    └── lty/                       # Loyalty channel
        ├── main.tf                # Terraform wiring + secret injection
        └── config.yml.tmpl        # Synthetics + monitors for lty
```

## What We Manage

### 1. Synthetics (Uptime Checks)

Defined in each channel's `config.yml.tmpl`. These are HTTP checks that ping an endpoint on a schedule and alert if it stops responding or responds too slowly. Migrated from Splunk APM Synthetics.

### 2. Monitors (Metric Alerts)

Also defined in `config.yml.tmpl`. These evaluate a metric or APM trace query and alert when a threshold is crossed. Migrated from Splunk APM Detectors.

## How To

### Add a new synthetic test

1. Open the channel's `config.yml.tmpl` (e.g., `datadog/ins/config.yml.tmpl`)
2. Copy an existing synthetic block
3. Give it a **new unique key** (e.g., `ins_new_service_health_check`)
4. Update the name, URL, frequency, assertions, and message
5. If the URL contains secrets, add a `data "aws_secretsmanager_secret_version"` block in `main.tf` and use `${variable_name}` in the template
6. Create a PR — CI will show you the plan

### Add a new monitor/alert

1. Open the channel's `config.yml.tmpl`
2. Copy an existing monitor block
3. Give it a **new unique key**
4. Update the name, type, query, thresholds, priority, and message
5. Set the correct `monitor_priority` (1=P1 critical through 5=P5 info)
6. Add appropriate `@pagerduty-` or `@slack-` notification handles
7. Create a PR — CI will show you the plan

### Add a new channel

1. Create a new directory under `datadog/` (e.g., `datadog/new_channel/`)
2. Copy `main.tf` from an existing channel (e.g., `datadog/ins/main.tf`)
3. Update the S3 backend key to `datadog/new_channel/terraform.tfstate` (MUST be unique)
4. Update secret paths from `/ins/...` to `/new_channel/...`
5. Create a `config.yml.tmpl` with your synthetics and monitors
6. Create a PR

## Branch Naming Convention

| Prefix | Use for | Example |
|-|-|-|
| `feat/` | New monitors, synthetics, channels | `feat/ins-migrate-splunk-apm-synthetics` |
| `fix/` | Fixing broken monitors or thresholds | `fix/ins-error-rate-threshold-too-low` |
| `chore/` | Dependency updates, formatting | `chore/update-terraform-providers` |
| `docs/` | README or comment changes | `docs/add-lty-runbook-links` |
| `refactor/` | Restructuring without behavior change | `refactor/extract-common-monitor-template` |

Format: `<prefix>/<channel>-<description>`

## PR and CI/CD Workflow

1. Create a feature branch from `main`
2. Make changes to Terraform files
3. Push the branch and open a Pull Request
4. **CI automatically runs `terraform plan`** and posts the output as a PR comment
5. Reviewer checks the plan — sees exactly what will be created/changed/destroyed in Datadog
6. Reviewer approves and merges to `main`
7. **CI automatically runs `terraform apply`** — changes go live in Datadog
8. Verify in Datadog UI (Synthetics and Monitors pages)

## GitHub Secrets Required

These must be configured in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Description | Where to find it |
|-|-|-|
| `DD_API_KEY` | Datadog API key | Datadog → Settings → Access → API Keys |
| `DD_APP_KEY` | Datadog Application key | Datadog → Settings → Access → Application Keys |
| `AWS_ROLE_ARN` | IAM role ARN for Terraform | AWS IAM console |
| `AWS_REGION` | AWS region (`ap-southeast-2`) | Set to your region |
