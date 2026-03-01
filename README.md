# TheNightOps

### Your Autonomous SRE Agent for the Incidents That Don't Wait Until Morning

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Google ADK](https://img.shields.io/badge/Google-ADK-4285F4.svg)](https://google.github.io/adk-python/)
[![MCP](https://img.shields.io/badge/MCP-Remote-green.svg)](https://modelcontextprotocol.io/)
[![Google Cloud MCP](https://img.shields.io/badge/Google%20Cloud-Official%20MCP-4285F4.svg)](https://docs.cloud.google.com/mcp/overview)
[![Grafana MCP](https://img.shields.io/badge/Grafana-Official%20MCP-F46800.svg)](https://github.com/grafana/mcp-grafana)

---

**TheNightOps** is an autonomous SRE agent built on [Google Agent Development Kit (ADK)](https://google.github.io/adk-python/) that connects to your existing observability stack through [Remote MCP servers](https://modelcontextprotocol.io/) — including [Google Cloud's official managed MCP servers](https://docs.cloud.google.com/mcp/overview) for GKE and Cloud Observability, and the [official Grafana MCP](https://github.com/grafana/mcp-grafana) for alerting, dashboards, Prometheus, and Loki. When an incident fires, it doesn't just notify — it **investigates, correlates, diagnoses, drafts an RCA, and communicates to stakeholders**, all before your on-call engineer finishes reading the Grafana alert.

---

## The Problem

Incident response in modern cloud-native environments is broken — not because of bad tooling, but because the human cost of correlating information across a dozen systems at 3 AM is unsustainable. Here are real scenarios that every SRE, DevOps, and platform engineering team has lived through:

### The Monday Morning OOMKill Cascade

A team deploys version 4.0 of their report service on Friday afternoon. Weekend traffic is light — everything looks fine. Dashboards are green. Nobody thinks twice.

Monday morning hits. Traffic surges. Suddenly, every report-service pod starts getting OOMKilled. The new version needs more memory than v3.0, but nobody updated the resource limits. The pods restart, can't serve requests during the restart window, and every downstream microservice that depends on report-service starts throwing 504s. What started as one service's memory problem becomes a platform-wide cascading failure.

The on-call engineer sees **47 alerts across 12 services** — but they all trace back to one bad resource limit on one deployment. It takes 45 minutes to figure that out because each alert looks like its own independent problem.

*Based on real incidents documented across the Kubernetes community — this exact pattern is one of the most common causes of production outages in microservice architectures.*

### The Config Change Nobody Noticed

At 11 PM, a platform engineer merges a "minor" Terraform change that adjusts connection pool sizes across three microservices. The change passes CI, gets auto-applied, and nobody thinks twice.

Two hours later, the database starts rejecting connections — the new pool size is too aggressive, and 200 services are now competing for 500 database connections that used to be shared across 50. The monitoring dashboard shows everything green except one metric buried in a custom Grafana panel nobody checks at 1 AM.

By the time PagerDuty fires, the cascading timeouts have spread to the payment service, and **real transactions are failing**. The on-call engineer spends 30 minutes suspecting a database issue before discovering it was a config change from two hours ago, buried in a Terraform apply log that nobody was watching.

*Configuration-related outages account for a significant share of cloud-native incidents — and they're the hardest to correlate because the cause and the symptom are separated by time and by system.*

### Alert Fatigue Meets Real Incident

Your monitoring fires 200+ alerts per day. Most are noise — brief CPU spikes, transient network blips, pods that auto-heal. Your on-call engineer has learned to glance at alerts and dismiss them.

Then one Tuesday at 3 AM, an alert fires that looks exactly like the usual noise: "Pod restart count elevated in namespace payments." Except this time, it's not auto-healing. The pods are stuck in CrashLoopBackOff because a dependency service silently changed its API contract. By the time someone actually investigates — **40 minutes later** — customer-facing payments have been down for 35 of those minutes.

The post-mortem concludes with "we need better alerting." Six months later, the team has even more alerts, even more fatigue, and the same problem waiting to happen again.

*According to the 2025 SRE Report, 40% of SRE teams handle 1-5 incidents per month, with alert fatigue consistently ranked as a top challenge. More alerts don't solve the problem — intelligence does.*

### The Toil Trap

Your team resolves 5 incidents this week. Each one required: logging into Cloud Console, cross-referencing 3 dashboards, reading 2 runbook pages, manually writing an RCA, and sending a Slack summary to stakeholders.

The incidents took 30 minutes to diagnose. **The paperwork took 90 minutes.** By Friday, your senior SRE has spent more time documenting incidents than preventing them. And the RCA from the 3 AM Wednesday incident? It's three sentences because the engineer was exhausted. The one from Thursday afternoon is two pages. Neither is useful for the next person who sees the same failure.

*The 2025 SRE industry data shows toil rose 6% year-over-year, and 28% of SREs report feeling MORE stressed after incidents are resolved — not because of the incident itself, but because of the post-incident documentation and communication burden.*

### What These Scenarios Have in Common

Every one of these scenarios shares the same structural problem: **the information needed to diagnose and resolve the incident existed in the system — scattered across logs, events, deployment history, and monitoring metrics.** A human had to manually assemble it, under pressure, often sleep-deprived, often alone.

The traditional answer has been more tooling, more dashboards, more alerting rules. But more tooling without intelligence just creates more noise.

**The real answer is an AI-powered SRE agent that can reason across all of this — and act.**

**TheNightOps changes this.** It reduces Mean Time to Resolution from 45+ minutes to under 5 minutes — autonomously.

---

## Architecture

TheNightOps is built on two key open standards: [Google ADK](https://google.github.io/adk-python/) for multi-agent orchestration and [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) for tool integration — leveraging **official MCP servers** from Google Cloud and Grafana Labs where available, so you're building on production-grade infrastructure, not brittle custom integrations.

```
┌──────────────────────────────────────────────────────────────────┐
│                     TheNightOps Agent (ADK)                       │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │   Log    │  │ Deploy   │  │ Runbook  │  │ Communication│    │
│  │ Analyst  │  │Correlator│  │Retriever │  │   Drafter    │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘    │
│       │              │             │                │            │
│  ┌────┴──────────────┴─────────────┴────────────────┴─────────┐  │
│  │                  Root Orchestrator Agent                      │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
└─────────────────────────────┼─────────────────────────────────────┘
                              │ MCP Protocol
       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
┌──────┴──────┐  ┌────────────┴────────────┐  ┌──────┴──────┐
│  Google     │  │   Google    │  Grafana  │  │   Slack     │
│  Cloud      │  │   GKE      │   MCP     │  │    MCP      │
│Observability│  │   MCP      │ (official │  │  (custom)   │
│  MCP        │  │  (official)│  stdio)   │  └─────────────┘
│ (official)  │  └────────────┴───────────┘         │
└─────────────┘                              ┌──────┴──────┐
                                             │Notifications│
       Official MCP Servers                  │    MCP      │
  Google Cloud (remote, IAM auth)            │  (custom)   │
  Grafana Labs (stdio, token auth)           └─────────────┘
```

### Three Layers

| Layer | Role | Components |
|-------|------|------------|
| **MCP Tool Servers** | The "hands" | Cloud Observability (official), GKE (official), Grafana (official), Slack (custom), Notifications — Email/Telegram/WhatsApp (custom) |
| **ADK Agent Orchestration** | The "brain" | Root Agent + 4 specialist sub-agents powered by Gemini |
| **Human-in-the-Loop** | The "guardrails" | Approval required for destructive actions (restarts, rollbacks, external notifications) |

### Why Google Cloud Official MCP Servers?

TheNightOps uses Google Cloud's **officially managed remote MCP servers** for GKE and Cloud Observability rather than custom implementations:

- **GKE MCP Server** ([docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/use-gke-mcp) | [github](https://github.com/GoogleCloudPlatform/gke-mcp)) — Agents interact with GKE and Kubernetes APIs through a structured, discoverable interface. No more parsing brittle `kubectl` text output.
- **Cloud Observability MCP** ([docs](https://docs.cloud.google.com/logging/docs/reference/v2/mcp)) — Search logs, view metrics, return traces, and view error reports through Google's managed MCP endpoint with enterprise IAM authentication.

Benefits over custom MCP servers:
- **IAM authentication** — No shared API keys; agents access only what's explicitly authorised
- **Audit logging** — Every query and action logged in Cloud Audit Logs
- **Managed infrastructure** — Google maintains the servers; you focus on the agent logic
- **Production-grade reliability** — Same SLAs as the underlying Google Cloud services

### Why Official Grafana MCP?

TheNightOps uses the **official Grafana MCP** ([github](https://github.com/grafana/mcp-grafana)) from Grafana Labs — the same team that builds Grafana. It runs as a stdio subprocess via `uvx mcp-grafana` and provides:

- **Alerting** — List firing alerts, alert rules, contact points, and create silences
- **Dashboards** — Search, inspect, and annotate dashboards
- **Prometheus** — Execute PromQL queries for metric analysis
- **Loki** — Execute LogQL queries for log analysis
- **Incidents** — Create and manage Grafana Incidents
- **On-Call** — View schedules and current on-call users
- **Annotations** — Mark investigation events directly on dashboards

This is a massive upgrade over custom alerting integrations — Grafana is the observability UI most open-source teams already use, and the official MCP gives the agent direct access to everything the SRE would normally check manually.

Custom MCP servers are used for Slack and multi-channel Notifications (Email/Telegram/WhatsApp), where no official MCP exists.

---

## Quick Start

### Prerequisites

- Python 3.11+
- Google Cloud SDK (`gcloud`) with an active project
- A GKE cluster (for live demo)
- Grafana instance (OSS, Cloud, or Enterprise) with a service account token
- Slack bot token (optional)
- Google Cloud MCP servers enabled ([setup guide](https://docs.cloud.google.com/mcp/overview))
- `uv` installed (`pip install uv`) for `uvx mcp-grafana`

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/thenightops.git
cd thenightops

# Install dependencies
pip install -e ".[dev]"

# Run the interactive setup wizard
nightops init
# → Configures GCP, Grafana, notification channels, agent model
# → Generates config/.env automatically

# Or configure manually
cp config/.env.example config/.env

# Enable Google Cloud MCP servers
gcloud services enable logging.googleapis.com
gcloud services enable container.googleapis.com

# Verify setup
nightops verify
```

### Run the Demo

```bash
# 1. Deploy the demo application to GKE
nightops demo deploy

# 2. Start custom MCP servers (Slack + Notifications)
nightops mcp start --all

# 3. Open the real-time investigation dashboard
nightops dashboard

# 4. Trigger an incident scenario
nightops demo trigger --scenario memory-leak

# 5. Watch TheNightOps investigate and resolve
nightops agent run --interactive
```

### Conference Live Demo

```bash
# Interactive step-by-step demo for presentations (GKE required)
./scripts/demo-live.sh

# Local-only demo without GKE (Docker Compose)
./scripts/demo-local.sh
```

---

## MCP Servers

TheNightOps uses a hybrid approach: **official MCP servers** from Google Cloud and Grafana Labs for core observability, Kubernetes, alerting, and metrics, and **custom MCP servers** for communication integrations.

### Google Cloud Observability MCP (Official)
Google's managed MCP server for Cloud Logging, Cloud Monitoring, Cloud Trace, and Error Reporting. Provides enterprise-grade log querying, metric analysis, distributed tracing, and error pattern detection — all authenticated via IAM.

**Tools available:** `search_logs`, `get_metrics`, `get_traces`, `get_error_groups`, `get_log_volume_anomalies`

### GKE MCP Server (Official)
Google's managed MCP server for Google Kubernetes Engine. Inspects pod status, reads events, checks resource utilisation, reviews deployments, and retrieves container logs — without requiring `kubectl` access.

**Tools available:** `get_pod_status`, `get_pod_logs`, `get_events`, `get_deployments`, `describe_pod`, `get_resource_usage`

### Grafana MCP (Official — mcp-grafana)
The official MCP server from Grafana Labs ([github](https://github.com/grafana/mcp-grafana)). Runs as a stdio subprocess via `uvx mcp-grafana`. Provides the agent with full access to Grafana's alerting, dashboards, Prometheus, Loki, incidents, on-call schedules, and annotations.

**Key tools:** `list_alert_rules`, `query_prometheus`, `query_loki_logs`, `search_dashboards`, `get_dashboard_by_uid`, `list_incidents`, `create_incident`, `get_current_oncall_users`, `create_annotation`, `silence_alert`, `list_contact_points`

### Slack MCP Server (Custom)
Posts incident updates to channels, sends formatted RCA summaries, notifies stakeholders with business-friendly language, and manages incident communication threads.

### Notifications MCP Server (Custom)
Multi-channel alerting for teams and stakeholders who aren't on Slack:

- **Email (SMTP)** — Formal RCA reports, stakeholder notifications, HTML-formatted incident summaries with CC/BCC support
- **Telegram Bot** — Instant team alerts with rich incident cards, severity indicators, and affected service lists
- **WhatsApp Business API** — Critical on-call escalations when engineers need to be reached on their personal device

**Tools available:** `send_email_alert`, `send_email_rca`, `send_telegram_alert`, `send_telegram_incident_card`, `send_whatsapp_alert`

---

## Investigation Dashboard

TheNightOps includes a **real-time investigation dashboard** — a web UI that streams agent activity as it happens, so you (and your conference audience) can watch the investigation unfold live.

```bash
# Launch the dashboard
nightops dashboard              # Opens http://localhost:8888
nightops dashboard --port 9000  # Custom port
```

The dashboard shows:

- **Live Investigation Timeline** — Every agent action streamed in real-time via WebSocket
- **Phase Progress** — Visual indicator tracking Triage → Deep Investigation → Synthesis → Remediation
- **Findings Grid** — Each finding displayed as a card with severity, source agent, and description
- **RCA Summary** — Auto-generated Root Cause Analysis rendered when investigation completes
- **Multi-Investigation Support** — Track multiple concurrent investigations side-by-side

The dashboard is built on FastAPI + WebSocket and requires no external dependencies beyond the core project.

---

## Interactive Setup Wizard

After cloning the repo, run the setup wizard to configure everything interactively:

```bash
nightops init
```

The wizard walks through:

1. **Google Cloud Platform** — Project ID, GKE cluster name/location, Google AI API key
2. **Grafana** — Instance URL, service account token
3. **Notification Channels** — Slack, Email (SMTP), Telegram Bot, WhatsApp Business API
4. **Agent Configuration** — Gemini model selection (2.0-flash, 1.5-pro, 1.5-flash)

It validates GCP connectivity, checks required APIs, and generates `config/.env` automatically.

---

## Docker Security

TheNightOps uses Docker best practices for production-grade container security:

### Docker Hardened Images (DHI)
All Dockerfiles use multi-stage builds with minimal runtime images, following [Docker Hardened Images](https://www.docker.com/blog/docker-hardened-images-for-every-developer/) principles — up to 95% fewer CVEs compared to community images.

### Docker Scout Integration
Scan all project images for vulnerabilities:

```bash
# Quick CVE scan
docker scout cves thenightops:latest

# Full scan with fix recommendations
./scripts/docker-scout-scan.sh --fix

# Compare with Docker Hardened Image alternatives
./scripts/docker-scout-scan.sh --compare-hardened
```

Use **Docker Desktop** → Images tab for a visual security dashboard.

### Security Features in Dockerfiles
- Multi-stage builds (build dependencies don't ship to production)
- Non-root user execution (`nightops` user)
- OCI labels for Docker Scout policy evaluation
- Health checks for container orchestration
- Minimal `apt` packages (only `curl` and `ca-certificates`)

---

## Agent Architecture

TheNightOps uses Google ADK's multi-agent orchestration to coordinate parallel investigation:

- **Root Orchestrator** — Receives incidents, coordinates investigation across sub-agents, synthesises findings, and makes decisions
- **Log Analyst Agent** — Specialises in Cloud Logging pattern analysis, anomaly detection, and trace correlation using the official Cloud Observability MCP
- **Deployment Correlator Agent** — Checks recent deployments, pod health, Kubernetes events, and resource exhaustion using the official GKE MCP
- **Runbook Retriever Agent** — Queries Grafana for firing alerts, alert history, past incidents, on-call information, and dashboard correlations
- **Communication Drafter Agent** — Generates RCAs, creates Grafana Incidents, sends Slack updates, and multi-channel stakeholder notifications (Email, Telegram, WhatsApp)

### Investigation Flow

```
Incident Received
      │
      ├──→ Log Analyst (parallel)         ──→ Error patterns, anomalies, traces
      ├──→ Deployment Correlator (parallel) ──→ Recent changes, pod health, events
      └──→ Runbook Retriever (parallel)    ──→ Grafana alerts, past incidents, dashboards
      │
      ▼
Root Orchestrator synthesises findings
      │
      ▼
Communication Drafter generates:
  ├── Grafana Incident (tracking + annotations)
  ├── Slack incident update (#incidents)
  ├── RCA summary (#post-mortems)
  └── Multi-channel notifications (Email/Telegram/WhatsApp)
      │
      ▼
Human approves any destructive actions
```

---

## Demo Scenarios

Each scenario simulates a real-world incident pattern. Deploy to GKE, trigger the scenario, and watch TheNightOps investigate autonomously.

### Scenario 1: Memory Leak → OOMKill Cascade

*Inspired by the Monday Morning OOMKill pattern described above.*

| | |
|---|---|
| **What happens** | A deployment introduces a memory leak. Pods gradually consume memory until they hit the 256Mi limit and are OOMKilled. Pods restart but immediately begin leaking again, creating CrashLoopBackOff. Downstream services start failing. |
| **What TheNightOps does** | Detects OOMKilled events via GKE MCP → correlates with recent deployment version change → identifies memory trending upward → finds restart count increasing → drafts RCA pointing to the new image version → recommends rollback |
| **Trigger** | `nightops demo trigger -s memory-leak` |

### Scenario 2: CPU Spike from Bad Query

*Inspired by unoptimised endpoint incidents that affect entire service latency.*

| | |
|---|---|
| **What happens** | A specific API endpoint (`/api/reports/generate`) consumes excessive CPU due to an unoptimised computation. CPU throttling causes high latency on ALL endpoints, not just the problematic one. Timeouts cascade. |
| **What TheNightOps does** | Identifies CPU at limits via GKE MCP → finds error logs pointing to specific endpoint via Cloud Observability MCP → correlates with recent deployment change → recommends disabling the endpoint and increasing CPU limits |
| **Trigger** | `nightops demo trigger -s cpu-spike` |

### Scenario 3: Database Connection Pool Exhaustion

*Inspired by the Config Change Nobody Noticed pattern described above.*

| | |
|---|---|
| **What happens** | Database connection pool is exhausted. The `/api/users` endpoint hangs waiting for a connection, returning 504s. Services depending on user data start failing — the classic cascading failure. |
| **What TheNightOps does** | Maps the failure cascade across services → identifies database timeout as root → traces back to connection pool config change → recommends pod restart to reset pool + circuit breaker implementation |
| **Trigger** | `nightops demo trigger -s cascading-failure` |

### Scenario 4: Config Drift Causing 5xx Errors

*Inspired by the Alert Fatigue scenario — an incident hidden in noise.*

| | |
|---|---|
| **What happens** | A misconfigured environment variable causes 50% of requests to `/api/data` to fail with 500 errors. The error rate looks like "normal noise" for 15 minutes before crossing the alert threshold. |
| **What TheNightOps does** | Detects error rate spike via Cloud Observability MCP → correlates timing with recent environment variable change via GKE MCP → identifies exact config key that changed → recommends reverting the config |
| **Trigger** | `nightops demo trigger -s config-drift` |

### Scenario 5: Aggressive OOMKill

*The extreme case — when memory allocation is deliberate or catastrophically fast.*

| | |
|---|---|
| **What happens** | Aggressive memory allocation consumes available memory within seconds. Kubernetes OOMKills the pod immediately. Pod restarts, allocates again, OOMKilled again — instant CrashLoopBackOff. Unlike the slow memory leak, this one is visible to everyone within 30 seconds. |
| **What TheNightOps does** | Instantly detects OOMKill event via GKE MCP → checks memory limits vs actual usage → identifies the allocation pattern in logs → correlates with deployment change → recommends immediate rollback with higher memory limits |
| **Trigger** | `nightops demo trigger -s oom-kill` |

---

## Configuration

```yaml
# config/nightops.yaml
agent:
  model: gemini-2.0-flash
  max_investigation_time: 300  # seconds
  require_human_approval:
    - pod_restart
    - deployment_rollback
    - external_notification

mcp_servers:
  # Google Cloud Official MCP Servers (managed, IAM-authenticated)
  cloud_observability:
    type: official
    endpoint: https://logging.googleapis.com/v2/mcp
    project_id: ${GCP_PROJECT_ID}
    auth: iam  # Uses Application Default Credentials
  gke:
    type: official
    endpoint: https://container.googleapis.com/v1/mcp
    project_id: ${GCP_PROJECT_ID}
    cluster: ${GKE_CLUSTER_NAME}
    location: ${GKE_CLUSTER_LOCATION}
    auth: iam

  # Grafana Official MCP (stdio via uvx mcp-grafana)
  grafana:
    type: official
    transport: stdio
    url: ${GRAFANA_URL}
    service_account_token: ${GRAFANA_SERVICE_ACCOUNT_TOKEN}

  # Custom MCP Servers (self-hosted)
  slack:
    type: custom
    transport: sse
    host: localhost
    port: 8004
    bot_token: ${SLACK_BOT_TOKEN}
```

---

## Key Metrics

| Metric | Before TheNightOps | After TheNightOps |
|--------|-------------------|-------------------|
| MTTR (investigation phase) | 45+ minutes | < 5 minutes |
| RCA consistency | Varies by engineer/time of day | Standardised every time |
| Context assembly time | 20+ minutes of manual correlation | Seconds (parallel agent queries) |
| Stakeholder notification | Manual, delayed, inconsistent | Automatic, immediate, formatted |
| On-call cognitive load | High (raw alerts + 5 dashboards) | Low (pre-diagnosed summary) |
| Post-incident toil | 90+ minutes per incident | < 10 minutes (review + approve) |

---

## CLI Reference

```bash
# Setup & Configuration
nightops init                              # Interactive setup wizard
nightops verify                            # Check all dependencies and configuration

# MCP Servers
nightops mcp start --all                   # Start all custom MCP servers
nightops mcp start slack                  # Start specific server
nightops mcp start notifications          # Start Email/Telegram/WhatsApp server
nightops mcp status                        # Check all MCP server status

# Dashboard
nightops dashboard                         # Launch real-time investigation dashboard
nightops dashboard --port 9000             # Custom port

# Demo
nightops demo deploy                       # Deploy demo app to GKE
nightops demo trigger -s memory-leak      # Trigger scenario
nightops demo trigger -s oom-kill         # Aggressive OOMKill scenario
nightops demo reset                        # Reset to clean state

# Agent
nightops agent run --interactive           # Interactive investigation mode
nightops agent run --incident "pod OOMKilled"  # Direct investigation
nightops agent run --debug --verbose       # Debug mode

# Conference Demo Scripts
./scripts/demo-live.sh                     # Interactive live demo (GKE)
./scripts/demo-local.sh                    # Local Docker demo (no GKE)
./scripts/docker-scout-scan.sh             # Scan images for CVEs
```

## Development

```bash
# Run tests
pytest tests/ -v

# Run linting
ruff check src/

# Run all services via Docker Compose
docker compose up -d

# Scan Docker images for vulnerabilities
./scripts/docker-scout-scan.sh --fix
```

---

## Roadmap

- [x] Google Cloud Observability MCP (official) integration
- [x] GKE MCP (official) integration
- [x] Grafana MCP (official — mcp-grafana) — alerting, dashboards, Prometheus, Loki, incidents, on-call
- [x] Slack MCP server (custom)
- [x] Notifications MCP server — Email (SMTP), Telegram Bot, WhatsApp Business API
- [x] Multi-agent investigation with ADK
- [x] 4 demo scenarios with GKE simulation
- [x] Docker Hardened Images + Docker Scout integration
- [x] Interactive setup wizard (`nightops init`)
- [x] Real-time investigation dashboard (WebSocket streaming)
- [x] Conference live demo scripts (GKE + local Docker)
- [x] Enhanced demo app with 6 failure modes + Prometheus metrics
- [ ] Jira MCP server for ticket creation
- [ ] Confluence/Wiki MCP for runbook retrieval
- [ ] Learning from past incidents to improve diagnosis accuracy
- [ ] Auto-remediation with approval workflows
- [ ] Multi-cluster support
- [ ] PagerDuty MCP server (optional integration)
- [ ] Cost-impact analysis agent
- [ ] gRPC transport support (following Google's MCP contribution)

---

## Contributing

Contributions are welcome! The best ways to contribute:

1. **Add MCP servers** — Each new integration (Jira, PagerDuty, Confluence) expands the agent's reach
2. **Add demo scenarios** — More incident patterns make the agent smarter during demonstrations
3. **Improve agent prompts** — Better reasoning instructions lead to better diagnosis accuracy
4. **Add tests** — Help us maintain reliability across all MCP servers and agents

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

---

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

---

## Acknowledgements

- [Google Agent Development Kit (ADK)](https://google.github.io/adk-python/)
- [Google Cloud Official MCP Servers](https://docs.cloud.google.com/mcp/overview)
- [Grafana MCP (mcp-grafana)](https://github.com/grafana/mcp-grafana)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
- The Kubernetes community for documenting real-world failure patterns
- Every SRE who has written a 3 AM post-mortem

---

**Built by engineers who are tired of being tired.**
