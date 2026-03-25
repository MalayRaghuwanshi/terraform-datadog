# Terraform-Datadog Monitoring

Manages all Datadog monitoring resources (synthetics and monitors) via Terraform, stored in GitHub, and deployed through CI/CD.

---

## What is Terraform?

**Terraform** is an open-source Infrastructure as Code (IaC) tool by HashiCorp. Instead of clicking buttons in a web UI to create infrastructure (servers, databases, monitoring alerts, etc.), you write **configuration files** that describe what you want, and Terraform creates it for you.

### Why use Terraform instead of the Datadog UI?

| Clicking in Datadog UI | Using Terraform |
|-|-|
| No record of who changed what | Every change is a Git commit with author + timestamp |
| Easy to accidentally delete a monitor | Changes are reviewed in a PR before going live |
| Can't roll back easily | `git revert` undoes any change instantly |
| Hard to replicate across environments | Same config deploys to dev, staging, prod |
| No approval process | PRs require reviewer approval before apply |
| One person's mistake affects everyone | CI catches errors before they reach production |

### How Terraform works — the 3-step cycle

```
 1. WRITE    →    2. PLAN    →    3. APPLY
 (edit .tf)      (preview)       (make it real)
```

1. **Write** — You edit `.tf` files (or `.yml.tmpl` templates) describing what you want
2. **Plan** — `terraform plan` compares your files to what currently exists in Datadog and shows a diff:
   - `+` = will be created
   - `~` = will be modified
   - `-` = will be destroyed
3. **Apply** — `terraform apply` executes the plan and makes the changes live

### Core Terraform concepts

| Concept | What it means | Example in this repo |
|-|-|-|
| **Provider** | A plugin that talks to an API | `DataDog/datadog` provider talks to the Datadog API |
| **Resource** | A single thing Terraform manages | `datadog_synthetics_test`, `datadog_monitor` |
| **State** | Terraform's record of what it created | Stored in S3 at `acme-terraform-state` bucket |
| **Module** | Reusable group of Terraform config | `common_vars/` is a module shared by all channels |
| **Backend** | Where the state file is stored | S3 bucket — not local, so CI/CD can access it |
| **Data source** | Read-only lookup (doesn't create anything) | `aws_secretsmanager_secret_version` reads a secret |

### Terraform file types

| Extension | Purpose |
|-|-|
| `.tf` | Terraform configuration (HCL syntax) |
| `.tfvars` | Variable values (often contains secrets — NEVER commit) |
| `.tfstate` | State file (contains real resource IDs — NEVER commit) |
| `.yml.tmpl` | Template file processed by Terraform's `template_file` data source |

---

## Terraform Syntax for Datadog Alerting

### The `.tf` file (HCL syntax)

Terraform uses **HCL (HashiCorp Configuration Language)**. Here are the building blocks:

#### Block structure

```hcl
# Every block has a TYPE, optional LABELS, and a BODY in { }
block_type "label1" "label2" {
  argument1 = "value"
  argument2 = 42

  nested_block {
    nested_arg = true
  }
}
```

#### Provider — tells Terraform how to authenticate to Datadog

```hcl
# The Datadog provider reads DD_API_KEY and DD_APP_KEY from environment variables
provider "datadog" {
  # api_key and app_key can be set here, but it's better to use env vars
  # so credentials never appear in code
}
```

#### Resource — a Datadog monitor written directly in HCL

```hcl
resource "datadog_monitor" "my_cpu_alert" {
  name    = "High CPU Usage"
  type    = "metric alert"
  query   = "avg(last_5m):avg:system.cpu.user{service:my-app} > 90"
  message = "CPU is above 90%! @slack-oncall"

  monitor_thresholds {
    critical = 90
    warning  = 75
  }

  tags = ["env:production", "team:platform"]
}
```

#### Resource — a Datadog synthetic test in HCL

```hcl
resource "datadog_synthetics_test" "my_health_check" {
  name      = "My App — Health Check"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = ["aws:us-east-1"]

  request_definition {
    method = "GET"
    url    = "https://my-app.example.com/health"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "3000"
  }

  options_list {
    tick_every = 300   # every 5 minutes
  }

  message = "Health check is failing! @pagerduty-MY_APP_P2"
}
```

### The `.yml.tmpl` file (template approach used in this repo)

In this repo, instead of writing raw HCL for each monitor, we use a **YAML template** that a shared Terraform module reads. This is easier for teams to work with — you just fill in YAML fields instead of learning HCL.

#### Anatomy of a monitor in config.yml.tmpl

```yaml
monitors:
  # The key — MUST be unique. Terraform uses this to track the resource.
  # Changing the key = Terraform destroys the old monitor and creates a new one.
  my_unique_monitor_key:

    # Display name in Datadog UI
    name: "My Team — Service Error Rate High"

    # Monitor type (see table below)
    type: "metric alert"

    # The Datadog query — what metric to watch and when to alert
    query: "avg(last_5m):sum:trace.servlet.request.errors{service:my-svc} > 5"

    # Thresholds — when to trigger each severity level
    monitor_thresholds:
      critical: 5           # Fire alert when metric > 5
      critical_recovery: 2  # Recover when metric drops below 2
      warning: 3            # Warning (less severe) at 3

    # Behavior settings
    require_full_window: false   # Don't wait for full 5min of data
    notify_no_data: true         # Alert if metric stops reporting
    no_data_timeframe: 10        # After 10 minutes of silence
    renotify_interval: 30        # Remind every 30 min if still alerting

    # Priority: 1=P1 critical, 2=P2 high, 3=P3 medium, 4=P4 low, 5=P5 info
    priority: 2

    # Alert message — WHO gets notified and WHAT they see
    message: |
      {{#is_alert}}
      Error rate is {{value}}% (threshold: {{threshold}}%)
      {{/is_alert}}
      {{#is_recovery}}
      Recovered. Current rate: {{value}}%
      {{/is_recovery}}
      @pagerduty-MY_TEAM_P2 @slack-my-team-alerts

    # Tags for filtering in Datadog UI
    tags:
      - "env:production"
      - "team:my-team"
      - "service:my-svc"
```

### Monitor types reference

| Type | When to use | Example query |
|-|-|-|
| `metric alert` | Alert on a numeric metric crossing a threshold | `avg(last_5m):avg:system.cpu.user{*} > 90` |
| `query alert` | Alert on a computed query (ratios, formulas) | `sum:errors / sum:hits * 100 > 5` |
| `service check` | Alert when a service stops reporting | `datadog.agent.check_status` |
| `log alert` | Alert on log patterns or counts | `logs("error service:my-app").index("*").rollup("count").last("5m") > 100` |
| `composite` | Combine multiple monitors with AND/OR logic | `1234 && 5678` (monitor IDs) |
| `anomaly` | Alert on unusual behavior vs. historical baseline | `avg(last_4h):anomalies(avg:system.cpu.user{*}, 'agile', 3)` |
| `forecast` | Alert when a metric is predicted to cross a threshold | `forecast(avg:system.disk.in_use{*}, 'linear', 1)` |

### Template syntax — the two systems in one file

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ${variable}        TERRAFORM syntax                                      │
│                    Replaced at terraform plan/apply time.                 │
│                    The value comes from AWS Secrets Manager or variables. │
│                    Datadog NEVER sees this — it's gone before upload.     │
│                                                                          │
│ {{#is_alert}}      DATADOG syntax                                        │
│ {{value}}          These ARE sent to Datadog and interpreted at alert     │
│ {{threshold}}      time. They show real metric values in notifications.   │
│ {{#is_recovery}}                                                         │
└──────────────────────────────────────────────────────────────────────────┘
```

### Datadog message template variables

| Variable | What it shows |
|-|-|
| `{{value}}` | The actual metric value that triggered the alert |
| `{{threshold}}` | The threshold that was crossed |
| `{{warn_threshold}}` | The warning threshold value |
| `{{url}}` | The URL being checked (synthetics only) |
| `{{#is_alert}}...{{/is_alert}}` | Block shown only when monitor is in ALERT state |
| `{{#is_warning}}...{{/is_warning}}` | Block shown only when monitor is in WARNING state |
| `{{#is_recovery}}...{{/is_recovery}}` | Block shown only when monitor recovers to OK |
| `{{#is_no_data}}...{{/is_no_data}}` | Block shown when no data is received |
| `{{host.name}}` | The hostname that triggered the alert |
| `{{last_triggered_at}}` | When the alert last fired |

### Notification routing

| Handle | Where it goes |
|-|-|
| `@slack-channel-name` | Posts to #channel-name in Slack |
| `@pagerduty-SERVICE_NAME` | Creates an incident in PagerDuty |
| `@teams-channel-name` | Posts to Microsoft Teams channel |
| `@email@example.com` | Sends an email |
| `@opsgenie-SERVICE` | Creates an alert in OpsGenie |

---

## Migration Context

This repository represents the migration from a **Legacy APM** platform to **Datadog**. All monitoring that previously lived in the legacy system — synthetics (uptime checks) and detectors (metric alerts) — is now defined as code here and managed through Pull Requests.

| Legacy APM Concept | Datadog Equivalent | Where in this repo |
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
    ├── alpha/                     # Alpha channel
    │   ├── main.tf                # Terraform wiring + secret injection
    │   └── config.yml.tmpl        # Synthetics + monitors for alpha
    └── beta/                      # Beta channel
        ├── main.tf                # Terraform wiring + secret injection
        └── config.yml.tmpl        # Synthetics + monitors for beta
```

## What We Manage

### 1. Synthetics (Uptime Checks)

Defined in each channel's `config.yml.tmpl`. These are HTTP checks that ping an endpoint on a schedule and alert if it stops responding or responds too slowly. Migrated from Legacy APM Synthetics.

### 2. Monitors (Metric Alerts)

Also defined in `config.yml.tmpl`. These evaluate a metric or APM trace query and alert when a threshold is crossed. Migrated from Legacy APM Detectors.

## How To

### Add a new synthetic test

1. Open the channel's `config.yml.tmpl` (e.g., `datadog/alpha/config.yml.tmpl`)
2. Copy an existing synthetic block
3. Give it a **new unique key** (e.g., `alpha_new_service_health_check`)
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

1. Create a new directory under `datadog/` (e.g., `datadog/gamma/`)
2. Copy `main.tf` from an existing channel (e.g., `datadog/alpha/main.tf`)
3. Update the S3 backend key to `datadog/gamma/terraform.tfstate` (MUST be unique)
4. Update secret paths from `/alpha/...` to `/gamma/...`
5. Create a `config.yml.tmpl` with your synthetics and monitors
6. Create a PR

## Branch Naming Convention

| Prefix | Use for | Example |
|-|-|-|
| `feat/` | New monitors, synthetics, channels | `feat/alpha-add-api-synthetics` |
| `fix/` | Fixing broken monitors or thresholds | `fix/alpha-error-rate-threshold-too-low` |
| `chore/` | Dependency updates, formatting | `chore/update-terraform-providers` |
| `docs/` | README or comment changes | `docs/add-beta-runbook-links` |
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
| `AWS_REGION` | AWS region (`us-east-1`) | Set to your region |
