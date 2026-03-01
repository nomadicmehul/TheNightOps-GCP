"""
Root Orchestrator Agent for TheNightOps.

The main agent that receives incidents and coordinates investigation
across all sub-agents using Google ADK's multi-agent orchestration.

Uses a hybrid MCP approach:
- Google Cloud's official managed MCP servers for GKE and Cloud Observability
- Official Grafana MCP (mcp-grafana) for alerting, dashboards, Prometheus, Loki, incidents, on-call
- Custom self-hosted MCP servers for Slack and Notifications

Enhanced with:
- Anomaly Detector sub-agent for proactive monitoring
- Incident Memory for pattern matching against historical incidents
- Graduated Remediation for safe auto-actions
- Impact Metrics for tracking effectiveness
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from google.adk.agents import Agent
from google.adk.tools.mcp_tool import MCPToolset, SseConnectionParams, StdioConnectionParams
from mcp import StdioServerParameters

from thenightops.agents.communication_drafter import create_communication_drafter_agent
from thenightops.agents.deployment_correlator import create_deployment_correlator_agent
from thenightops.agents.log_analyst import create_log_analyst_agent
from thenightops.agents.runbook_retriever import create_runbook_retriever_agent
from thenightops.agents.anomaly_detector import create_anomaly_detector_agent
from thenightops.core.config import NightOpsConfig

logger = logging.getLogger(__name__)

ROOT_ORCHESTRATOR_INSTRUCTION = """You are TheNightOps, an autonomous SRE agent that investigates
and helps resolve production incidents. You coordinate a team of specialist agents.

You operate on Google Cloud Platform and connect to infrastructure through
Google Cloud's official managed MCP servers (for GKE and Cloud Observability),
the official Grafana MCP (for alerting, dashboards, Prometheus, Loki, incidents, and on-call),
and custom MCP servers (for Slack and multi-channel Notifications).

## Your Sub-Agents

You have five specialist agents you can delegate to:

1. **log_analyst** — Analyses Cloud Logging via the official Google Cloud Observability MCP
   for error patterns, anomalies, metrics, traces, and error groups
2. **deployment_correlator** — Checks Kubernetes state via the official GKE MCP server
   for recent deployments, pod health, events, and resource exhaustion
3. **runbook_retriever** — Searches Grafana for alert history, past incidents, on-call
   schedules, and dashboard correlations to find similar past patterns
4. **communication_drafter** — Generates RCAs and stakeholder notifications via multiple
   channels: Slack, Email (SMTP), Telegram Bot, and WhatsApp Business API
5. **anomaly_detector** — Proactively monitors cluster health by checking pod status,
   memory trends, error rates, and resource usage to detect anomalies early

## Historical Context

Before investigating, check if this incident matches a known pattern. If the system
provides similar historical incidents, use that context to accelerate diagnosis:
- If a similar incident was resolved before, check if the same root cause applies
- If the pattern recurs, flag it as a recurring issue and recommend permanent fixes
- Use historical MTTR as a benchmark for this investigation

## Available Grafana MCP Tools

Through the official Grafana MCP, you have access to:
- `get_firing_alerts` / `list_alert_rules` — See what Grafana alerting thinks is wrong
- `query_prometheus` — Execute PromQL queries for metrics analysis
- `query_loki_logs` — Execute LogQL queries for log analysis
- `search_dashboards` / `get_dashboard_by_uid` — Find and inspect relevant dashboards
- `list_incidents` / `create_incident` — Manage Grafana Incidents
- `get_current_oncall_users` / `list_schedules` — Check on-call schedules
- `create_annotation` — Mark investigation events on dashboards
- `silence_alert` — Silence alerts during active investigation

## Investigation Protocol

When you receive an incident, follow this systematic approach:

### Phase 1: Initial Triage (Parallel)
Delegate simultaneously to:
- `log_analyst`: Check for log anomalies and error patterns via Cloud Observability MCP
- `deployment_correlator`: Check recent deployments and pod health via GKE MCP
- `runbook_retriever`: Check Grafana for firing alerts, alert history, past incidents,
  and on-call information

Additionally, use Grafana tools directly:
- `get_firing_alerts`: Get all currently firing Grafana alerts
- `query_prometheus`: Query key metrics (error rates, latency, saturation)
- `create_annotation`: Mark investigation start on relevant dashboards

### Phase 2: Deep Investigation
Based on Phase 1 findings, direct specific follow-up investigations:
- If deployment change detected → ask `deployment_correlator` to examine specific pods
- If error patterns found → ask `log_analyst` to correlate by trace ID
- If Grafana alerts point to specific service → use `query_prometheus` and `query_loki_logs`
  to get targeted metrics and logs
- If similar past incidents found → review past resolutions for applicable fixes

### Phase 3: Synthesis & Communication
Once you have sufficient evidence:
1. Synthesise all findings into a coherent diagnosis
2. Determine root cause with confidence level
3. Use `create_annotation` to mark root cause identified on dashboards
4. Use `silence_alert` to silence noisy alerts related to the diagnosed issue
5. Ask `communication_drafter` to:
   - Post incident status update to Slack (#incidents)
   - Draft an RCA summary for #post-mortems
   - Notify stakeholders of business impact in plain language
   - Create a Grafana Incident for tracking

### Phase 4: Remediation Recommendations
Based on your analysis:
- Suggest immediate actions (e.g., rollback deployment, restart pods)
- Flag which actions can be auto-approved vs require human approval
- Recommend long-term fixes to prevent recurrence
- Create annotation with resolution summary

## Remediation Policy

Actions are governed by graduated autonomy:
- **Auto-approved**: Silencing alerts, creating Grafana incidents, posting to #incidents
- **Environment-gated**: Pod restarts (auto in dev/staging, approval needed in prod)
- **Always require approval**: Rollbacks, scaling changes, external notifications
- **Blocked**: Namespace deletion, PVC deletion, cluster operations

## Decision Framework

- **High confidence root cause found**: Proceed to Phase 3 immediately
- **Multiple possible causes**: Investigate the most likely one first, note alternatives
- **No clear root cause after Phase 2**: Summarise what you've found, escalate to human
- **Recurring incident**: Highlight this pattern and recommend permanent fix
- **Proactive detection**: If anomaly_detector found this, note it was caught proactively

## Human-in-the-Loop

You MUST request human approval before:
- Restarting pods or services in production
- Rolling back deployments
- Sending external stakeholder notifications
- Any action that modifies the production environment

## Output Format

Present your final analysis as:

**Incident Summary**: [one line]
**Severity**: [critical/high/medium/low]
**Root Cause**: [concise explanation]
**Evidence**: [key findings from investigation]
**Impact**: [what's affected and how]
**Immediate Actions**: [what should be done now — mark auto-approved vs needs approval]
**Long-term Recommendations**: [prevent recurrence]
**Confidence Level**: [low/medium/high with reasoning]
**Historical Match**: [similar past incident if found, or "No matching historical pattern"]
"""


def create_mcp_toolsets(config: NightOpsConfig) -> list[MCPToolset]:
    """Create MCP toolset connections for all configured servers.

    Uses a hybrid approach:
    - Official Google Cloud MCP servers connect via their managed SSE endpoints
    - Official Grafana MCP connects via stdio (subprocess)
    - Custom MCP servers connect via local SSE transport
    """
    toolsets = []

    # ── Official Google Cloud MCP Servers ────────────────────────
    if config.cloud_observability.enabled:
        logger.info(
            "Connecting to official Cloud Observability MCP: %s (project: %s)",
            config.cloud_observability.endpoint,
            config.cloud_observability.project_id,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=config.cloud_observability.endpoint,
                    headers={
                        "x-goog-project-id": config.cloud_observability.project_id,
                    },
                ),
            )
        )

    if config.gke.enabled:
        logger.info(
            "Connecting to official GKE MCP: %s (cluster: %s/%s)",
            config.gke.endpoint,
            config.gke.location,
            config.gke.cluster,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=config.gke.endpoint,
                    headers={
                        "x-goog-project-id": config.gke.project_id,
                        "x-gke-cluster": config.gke.cluster,
                        "x-gke-location": config.gke.location,
                    },
                ),
            )
        )

    # ── Multi-Cluster GKE MCP connections ─────────────────────────
    for cluster_config in config.clusters:
        if not cluster_config.enabled:
            continue
        logger.info(
            "Connecting to GKE MCP for cluster: %s/%s (%s)",
            cluster_config.location, cluster_config.name, cluster_config.environment,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=cluster_config.gke_mcp_endpoint,
                    headers={
                        "x-goog-project-id": cluster_config.project_id,
                        "x-gke-cluster": cluster_config.name,
                        "x-gke-location": cluster_config.location,
                    },
                ),
            )
        )

    # ── Official Grafana MCP (stdio transport) ───────────────────
    if config.grafana.enabled:
        logger.info(
            "Connecting to official Grafana MCP: %s (stdio via uvx mcp-grafana)",
            config.grafana.url,
        )
        grafana_args = ["mcp-grafana"]
        if config.grafana.enabled_tools:
            grafana_args.extend(["--enabled-tools", config.grafana.enabled_tools])

        toolsets.append(
            MCPToolset(
                connection_params=StdioConnectionParams(
                    server_params=StdioServerParameters(
                        command="uvx",
                        args=grafana_args,
                        env={
                            "GRAFANA_URL": config.grafana.url,
                            "GRAFANA_SERVICE_ACCOUNT_TOKEN": config.grafana.service_account_token or "",
                        },
                    ),
                ),
            )
        )

    # ── Custom MCP Servers (self-hosted via SSE) ────────────────

    if config.kubernetes.enabled:
        logger.info(
            "Connecting to custom Kubernetes MCP: %s:%d",
            config.kubernetes.host,
            config.kubernetes.port,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=f"http://{config.kubernetes.host}:{config.kubernetes.port}/sse",
                ),
            )
        )

    if config.cloud_logging_custom.enabled:
        logger.info(
            "Connecting to custom Cloud Logging MCP: %s:%d",
            config.cloud_logging_custom.host,
            config.cloud_logging_custom.port,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=f"http://{config.cloud_logging_custom.host}:{config.cloud_logging_custom.port}/sse",
                ),
            )
        )

    if config.slack.enabled:
        logger.info(
            "Connecting to custom Slack MCP: %s:%d",
            config.slack.host,
            config.slack.port,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=f"http://{config.slack.host}:{config.slack.port}/sse",
                ),
            )
        )

    if config.notifications.enabled:
        logger.info(
            "Connecting to custom Notifications MCP: %s:%d (Email/Telegram/WhatsApp)",
            config.notifications.host,
            config.notifications.port,
        )
        toolsets.append(
            MCPToolset(
                connection_params=SseConnectionParams(
                    url=f"http://{config.notifications.host}:{config.notifications.port}/sse",
                ),
            )
        )

    return toolsets


def create_root_orchestrator(
    config: NightOpsConfig,
) -> Agent:
    """
    Create the root orchestrator agent with all sub-agents and MCP toolsets.

    Architecture:
    - Root Orchestrator coordinates 5 specialist sub-agents
    - Sub-agents access tools via MCP (Google Cloud official + Grafana official + custom)
    - All powered by Google ADK's multi-agent orchestration
    """
    model = config.agent.model

    # Create sub-agents
    log_analyst = create_log_analyst_agent(model=model)
    deployment_correlator = create_deployment_correlator_agent(model=model)
    runbook_retriever = create_runbook_retriever_agent(model=model)
    communication_drafter = create_communication_drafter_agent(model=model)
    anomaly_detector = create_anomaly_detector_agent(model=model)

    # Create MCP toolsets (Google Cloud official + Grafana official + custom)
    mcp_toolsets = create_mcp_toolsets(config)

    # Build the root orchestrator
    root_agent = Agent(
        name="thenightops",
        model=model,
        description=(
            "TheNightOps — Autonomous SRE agent that investigates production "
            "incidents by coordinating log analysis (via Cloud Observability MCP), "
            "deployment correlation (via GKE MCP), alert & metric analysis (via Grafana MCP), "
            "proactive anomaly detection, and stakeholder communication "
            "(via Slack + multi-channel Notifications)."
        ),
        instruction=ROOT_ORCHESTRATOR_INSTRUCTION,
        sub_agents=[
            log_analyst,
            deployment_correlator,
            runbook_retriever,
            communication_drafter,
            anomaly_detector,
        ],
        tools=[*mcp_toolsets],
    )

    official_count = sum([
        config.cloud_observability.enabled,
        config.gke.enabled,
        config.grafana.enabled,
    ])
    custom_count = sum([config.slack.enabled, config.notifications.enabled])
    cluster_count = sum(1 for c in config.clusters if c.enabled)

    logger.info(
        "Root orchestrator created with %d sub-agents, %d official MCP + %d custom MCP toolsets, %d extra clusters",
        5,
        official_count,
        custom_count,
        cluster_count,
    )

    return root_agent


async def run_investigation(
    config: NightOpsConfig,
    incident_description: str,
    dashboard_url: str | None = None,
    incident_id: str | None = None,
) -> dict[str, Any]:
    """
    Run a full incident investigation.

    Enhanced with:
    - Incident Memory: Finds similar historical incidents to accelerate diagnosis
    - Metrics Tracking: Records investigation metrics for impact reporting
    - Remediation Engine: Suggests auto-approvable vs manual actions
    """
    import httpx
    from google.adk.runners import Runner
    from google.adk.sessions import InMemorySessionService
    from google.genai import types

    # ── Intelligence Layer: Find similar historical incidents ────
    historical_context = ""
    if config.intelligence.enabled:
        try:
            from thenightops.intelligence.incident_memory import IncidentMemory
            memory = IncidentMemory(config.intelligence)
            similar = memory.find_similar(incident_description)
            if similar:
                historical_context = "\n\n## Historical Context (Similar Past Incidents)\n"
                for s in similar:
                    historical_context += (
                        f"\n- **{s.title}** (similarity: {s.similarity_score:.0%})\n"
                        f"  Root cause: {s.root_cause}\n"
                        f"  Resolution: {s.resolution}\n"
                        f"  MTTR: {s.mttr_seconds:.0f}s\n"
                    )
                logger.info("Found %d similar historical incidents", len(similar))
        except Exception:
            logger.debug("Incident memory not available, proceeding without history")

    # ── Remediation Policy Context ────────────────────────────────
    remediation_context = ""
    if config.remediation.enabled:
        try:
            from thenightops.remediation.policy_engine import PolicyEngine
            engine = PolicyEngine(config.remediation.policy_path)
            summary = engine.get_policy_summary()
            remediation_context = "\n\n## Remediation Policies\n"
            for action, status in summary.items():
                remediation_context += f"- {action}: {status}\n"
        except Exception:
            logger.debug("Remediation policies not available")

    agent = create_root_orchestrator(config)

    session_service = InMemorySessionService()
    session = await session_service.create_session(
        app_name="thenightops",
        user_id="nightops-system",
    )

    runner = Runner(
        agent=agent,
        app_name="thenightops",
        session_service=session_service,
    )

    # ── Dashboard integration ────────────────────────────────
    investigation_id_val: str | None = incident_id
    http_client: httpx.AsyncClient | None = None

    if dashboard_url:
        http_client = httpx.AsyncClient(base_url=dashboard_url, timeout=5.0)
        if not investigation_id_val:
            try:
                resp = await http_client.post(
                    "/api/investigations",
                    params={
                        "incident_description": incident_description,
                        "severity": "medium",
                    },
                )
                if resp.status_code == 200:
                    investigation_id_val = resp.json().get("id")
                    logger.info("Dashboard investigation created: %s", investigation_id_val)
            except Exception as exc:
                logger.warning("Could not register investigation on dashboard: %s", exc)

    async def _push_dashboard_event(event_data: dict) -> None:
        if not http_client or not investigation_id_val:
            return
        try:
            event_data["investigation_id"] = investigation_id_val
            await http_client.post("/api/events", json=event_data)
        except Exception:
            pass

    # Build enriched incident message with historical context
    enriched_message = f"INCIDENT RECEIVED:\n\n{incident_description}"
    if historical_context:
        enriched_message += historical_context
    if remediation_context:
        enriched_message += remediation_context

    user_message = types.Content(
        role="user",
        parts=[types.Part(text=enriched_message)],
    )

    results: list[str] = []
    tools_called = 0

    async for event in runner.run_async(
        user_id="nightops-system",
        session_id=session.id,
        new_message=user_message,
    ):
        fn_calls = event.get_function_calls()
        if fn_calls:
            for fc in fn_calls:
                tools_called += 1
                await _push_dashboard_event({
                    "type": "tool_called",
                    "agent": event.author or "thenightops",
                    "tool_name": fc.name,
                    "tool_input": str(fc.args)[:500],
                })

        fn_responses = event.get_function_responses()
        if fn_responses:
            for fr in fn_responses:
                await _push_dashboard_event({
                    "type": "finding_added",
                    "source_agent": event.author or "thenightops",
                    "severity": "medium",
                    "description": f"Tool {fr.name} returned data ({len(str(fr.response))} chars)",
                })

        if event.author and event.content and event.content.parts:
            for part in event.content.parts:
                if hasattr(part, "text") and part.text and not event.is_final_response():
                    await _push_dashboard_event({
                        "type": "agent_delegated",
                        "agent": event.author,
                        "task": part.text[:300],
                    })

        if event.is_final_response():
            for part in event.content.parts:
                if part.text:
                    results.append(part.text)

    investigation_result = "\n".join(results)

    await _push_dashboard_event({
        "type": "investigation_completed",
        "status": "completed",
        "rca_summary": investigation_result[:2000],
    })

    if http_client:
        await http_client.aclose()

    return {
        "session_id": session.id,
        "investigation_id": investigation_id_val,
        "investigation_result": investigation_result,
        "tools_called": tools_called,
        "historical_matches": len(historical_context.split("\n- ")) - 1 if historical_context else 0,
    }
