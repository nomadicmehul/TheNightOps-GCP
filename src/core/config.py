"""Configuration management for TheNightOps."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Literal, Optional

import yaml
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings


# ── Official Google Cloud MCP Server Configs ────────────────────────


class CloudObservabilityConfig(BaseSettings):
    """Google Cloud Observability MCP server configuration (official, managed).

    Uses Google's managed remote MCP server for Cloud Logging, Cloud Monitoring,
    Cloud Trace, and Error Reporting. Authenticated via IAM — no API keys needed.

    Docs: https://docs.cloud.google.com/logging/docs/reference/v2/mcp
    """

    type: Literal["official"] = "official"
    endpoint: str = "https://logging.googleapis.com/v2/mcp"
    project_id: str = Field(default="", description="GCP project ID")
    auth: str = "iam"  # Uses Application Default Credentials
    enabled: bool = True


class GKEMCPConfig(BaseSettings):
    """Google Kubernetes Engine MCP server configuration (official, managed).

    Uses Google's managed remote MCP server for GKE. Provides structured access
    to Kubernetes resources without requiring kubectl.

    Docs: https://docs.cloud.google.com/kubernetes-engine/docs/how-to/use-gke-mcp
    GitHub: https://github.com/GoogleCloudPlatform/gke-mcp
    """

    type: Literal["official"] = "official"
    endpoint: str = "https://container.googleapis.com/v1/mcp"
    project_id: str = Field(default="", description="GCP project ID")
    cluster: str = Field(default="", description="GKE cluster name")
    location: str = Field(default="", description="GKE cluster location (zone or region)")
    auth: str = "iam"
    enabled: bool = True


# ── Custom MCP Server Configs ───────────────────────────────────────


class CustomMCPServerConfig(BaseSettings):
    """Base configuration for a custom (self-hosted) MCP server."""

    type: Literal["custom"] = "custom"
    transport: str = "sse"
    host: str = "localhost"
    enabled: bool = True

    @field_validator("host", mode="before")
    @classmethod
    def default_empty_host(cls, v: str) -> str:
        """Default empty host to localhost (e.g. when env var is unresolved)."""
        return v if v else "localhost"


class GrafanaConfig(BaseSettings):
    """Grafana MCP server configuration (official, stdio-based).

    Uses the official mcp-grafana server from Grafana Labs.
    Runs as a subprocess via stdio transport (not SSE).
    Supports alerting, dashboards, Prometheus, Loki, incidents, on-call.

    GitHub: https://github.com/grafana/mcp-grafana
    Install: uvx mcp-grafana
    """

    type: Literal["official"] = "official"
    transport: str = "stdio"
    url: str = Field(default="http://localhost:3000", description="Grafana instance URL")
    service_account_token: Optional[str] = Field(default="", description="Grafana service account token")
    enabled: bool = True
    enabled_tools: str = ""  # Comma-separated extra tool categories to enable


class KubernetesConfig(CustomMCPServerConfig):
    """Kubernetes MCP server configuration (custom, self-hosted)."""

    port: int = 8002


class CloudLoggingCustomConfig(CustomMCPServerConfig):
    """Cloud Logging MCP server configuration (custom, self-hosted)."""

    port: int = 8001
    project_id: str = Field(default="", description="GCP project ID")


class SlackConfig(CustomMCPServerConfig):
    """Slack MCP server configuration (custom, self-hosted)."""

    port: int = 8004
    bot_token: str = Field(default="", description="Slack bot token")
    incident_channel: str = "#incidents"
    rca_channel: str = "#post-mortems"


class NotificationsConfig(CustomMCPServerConfig):
    """Notifications MCP server configuration (custom, self-hosted).

    Multi-channel alerting: Email (SMTP), Telegram Bot, WhatsApp Business API.
    """

    port: int = 8005
    # Email (SMTP)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    from_email: str = ""
    # Telegram
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    # WhatsApp Business API
    whatsapp_api_url: str = ""
    whatsapp_api_token: str = ""
    whatsapp_phone_number: str = ""


# ── Multi-Cluster Config ──────────────────────────────────────────


class ClusterConfig(BaseSettings):
    """Configuration for a single Kubernetes cluster."""

    name: str = ""
    project_id: str = ""
    location: str = ""
    environment: str = "production"  # production, staging, development
    criticality: str = "high"  # high, medium, low
    gke_mcp_endpoint: str = "https://container.googleapis.com/v1/mcp"
    enabled: bool = True


# ── Ingestion Config ──────────────────────────────────────────────


class WebhookConfig(BaseSettings):
    """Webhook ingestion configuration."""

    enabled: bool = True
    host: str = "0.0.0.0"
    port: int = 8090
    # Deduplication
    dedup_window_seconds: int = 300  # 5 minute sliding window
    max_alerts_per_window: int = 100


class EventWatcherConfig(BaseSettings):
    """Kubernetes event watcher configuration."""

    enabled: bool = True
    namespaces: list[str] = Field(default_factory=lambda: ["default"])
    watch_reasons: list[str] = Field(
        default_factory=lambda: [
            "OOMKilled",
            "CrashLoopBackOff",
            "FailedScheduling",
            "Unhealthy",
            "BackOff",
            "FailedMount",
            "FailedAttachVolume",
        ]
    )
    min_severity_to_alert: str = "Warning"


# ── Intelligence Config ───────────────────────────────────────────


class IntelligenceConfig(BaseSettings):
    """Incident memory / vector store configuration."""

    enabled: bool = True
    store_path: str = "data/incident_store"  # Local JSON store path
    max_similar_results: int = 5
    similarity_threshold: float = 0.3


# ── Remediation Config ────────────────────────────────────────────


class RemediationConfig(BaseSettings):
    """Remediation policy engine configuration."""

    enabled: bool = True
    policy_path: str = "config/remediation_policies.yaml"
    default_require_approval: bool = True


# ── Proactive Detection Config ────────────────────────────────────


class ProactiveConfig(BaseSettings):
    """Proactive anomaly detection configuration."""

    enabled: bool = True
    check_interval_seconds: int = 300  # 5 minutes
    checks: list[str] = Field(
        default_factory=lambda: [
            "crashloop_pods",
            "oom_killed",
            "memory_trending",
            "error_rate_spike",
            "deployment_zero_ready",
        ]
    )
    memory_threshold_percent: float = 85.0
    error_rate_multiplier: float = 2.0  # 2x above baseline = anomalous


# ── Metrics Config ────────────────────────────────────────────────


class MetricsConfig(BaseSettings):
    """Impact metrics tracking configuration."""

    enabled: bool = True
    store_path: str = "data/metrics"
    estimated_manual_mttr_seconds: float = 2700.0  # 45 minutes baseline


# ── Agent Config ────────────────────────────────────────────────────


# Supported Gemini models
SUPPORTED_MODELS = [
    # Gemini 3.x series
    "gemini-3.1-pro",
    "gemini-3-flash",
    # Gemini 2.x series
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    # Gemini 1.5 series (legacy)
    "gemini-1.5-pro",
    "gemini-1.5-flash",
]


class AgentConfig(BaseSettings):
    """ADK agent configuration."""

    model: str = "gemini-2.5-flash"
    max_investigation_time: int = 300  # seconds
    max_agent_turns: int = 20
    require_human_approval: list[str] = Field(
        default_factory=lambda: [
            "pod_restart",
            "deployment_rollback",
            "external_notification",
        ]
    )
    verbose: bool = False


# ── Root Config ─────────────────────────────────────────────────────


class NightOpsConfig(BaseSettings):
    """Root configuration for TheNightOps.

    Supports three types of MCP servers:
    - Official Google Cloud MCP (managed, IAM-authenticated, SSE transport)
    - Official Grafana MCP (mcp-grafana, stdio transport)
    - Custom MCP (self-hosted SSE servers for Slack, Notifications)
    """

    agent: AgentConfig = Field(default_factory=AgentConfig)

    # Official MCP Servers
    cloud_observability: CloudObservabilityConfig = Field(
        default_factory=CloudObservabilityConfig
    )
    gke: GKEMCPConfig = Field(default_factory=GKEMCPConfig)
    grafana: GrafanaConfig = Field(default_factory=GrafanaConfig)

    # Custom MCP Servers
    kubernetes: KubernetesConfig = Field(default_factory=KubernetesConfig)
    cloud_logging_custom: CloudLoggingCustomConfig = Field(default_factory=CloudLoggingCustomConfig)
    slack: SlackConfig = Field(default_factory=SlackConfig)
    notifications: NotificationsConfig = Field(default_factory=NotificationsConfig)

    # Multi-cluster support
    clusters: list[ClusterConfig] = Field(default_factory=list)

    # New capabilities
    webhook: WebhookConfig = Field(default_factory=WebhookConfig)
    event_watcher: EventWatcherConfig = Field(default_factory=EventWatcherConfig)
    intelligence: IntelligenceConfig = Field(default_factory=IntelligenceConfig)
    remediation: RemediationConfig = Field(default_factory=RemediationConfig)
    proactive: ProactiveConfig = Field(default_factory=ProactiveConfig)
    metrics: MetricsConfig = Field(default_factory=MetricsConfig)

    @classmethod
    def from_yaml(cls, path: str | Path) -> NightOpsConfig:
        """Load configuration from a YAML file with environment variable substitution."""
        path = Path(path)
        if not path.exists():
            raise FileNotFoundError(f"Configuration file not found: {path}")

        with open(path) as f:
            raw = f.read()

        # Substitute environment variables (${VAR_NAME} syntax)
        for key, value in os.environ.items():
            raw = raw.replace(f"${{{key}}}", value)

        # Replace any remaining unresolved ${VAR} references with empty string
        raw = re.sub(r"\$\{[A-Za-z_][A-Za-z0-9_]*\}", "", raw)

        data = yaml.safe_load(raw)

        # Handle nested mcp_servers key if present in YAML
        if "mcp_servers" in data:
            mcp = data.pop("mcp_servers")
            # Map YAML key cloud_logging → cloud_logging_custom to avoid conflict
            if "cloud_logging" in mcp:
                mcp["cloud_logging_custom"] = mcp.pop("cloud_logging")
            data.update(mcp)

        return cls(**data)

    @classmethod
    def load(cls, config_path: Optional[str | Path] = None) -> NightOpsConfig:
        """Load config from file or use defaults with environment variables."""
        if config_path and Path(config_path).exists():
            return cls.from_yaml(config_path)

        # Try default locations
        for default_path in ["config/nightops.yaml", "nightops.yaml"]:
            if Path(default_path).exists():
                return cls.from_yaml(default_path)

        # Fall back to environment variables and defaults
        project_id = os.getenv("GCP_PROJECT_ID", "")
        return cls(
            cloud_observability=CloudObservabilityConfig(
                project_id=project_id,
            ),
            gke=GKEMCPConfig(
                project_id=project_id,
                cluster=os.getenv("GKE_CLUSTER_NAME", ""),
                location=os.getenv("GKE_CLUSTER_LOCATION", ""),
            ),
            grafana=GrafanaConfig(
                url=os.getenv("GRAFANA_URL", "http://localhost:3000"),
                service_account_token=os.getenv("GRAFANA_SERVICE_ACCOUNT_TOKEN", ""),
            ),
            slack=SlackConfig(
                bot_token=os.getenv("SLACK_BOT_TOKEN", ""),
            ),
        )
