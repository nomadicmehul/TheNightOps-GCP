"""
Enhanced Demo Application for TheNightOps.

A production-quality FastAPI application that simulates various failure modes
for demonstrating TheNightOps incident investigation capabilities.

Features:
  - Health/readiness/metrics endpoints for Kubernetes probes
  - Request and error tracking with Prometheus-style metrics
  - Multiple failure modes (memory-leak, cpu-spike, cascading-failure, config-drift, oom-kill)
  - Order processing endpoint with failure simulation
  - Detailed status tracking with uptime, error rates, and performance metrics
  - Structured JSON logging for analysis

Run this in a container on GKE, in a kind cluster, or locally for testing.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import psutil
import random
import sys
import threading
import time
from datetime import datetime
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse
import uvicorn

# ── Structured Logging Setup ───────────────────────────────────────

class StructuredFormatter(logging.Formatter):
    """Formats logs as JSON for better analysis."""

    def format(self, record: logging.LogRecord) -> str:
        log_data: dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_data)


def setup_logging() -> logging.Logger:
    """Configure structured JSON logging."""
    logger = logging.getLogger("nightops-demo-api")
    logger.setLevel(logging.INFO)

    # Console handler with structured format
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredFormatter())
    logger.addHandler(handler)

    return logger


logger = setup_logging()

# ── Configuration from Environment ──────────────────────────────────

FAILURE_MODE = os.getenv("FAILURE_MODE", "none")
LEAK_RATE_MB = int(os.getenv("LEAK_RATE_MB", "10"))
ERROR_RATE_PERCENT = int(os.getenv("ERROR_RATE_PERCENT", "5"))
CPU_SPIKE_DURATION_SEC = int(os.getenv("CPU_SPIKE_DURATION_SEC", "30"))
OOM_KILL_THRESHOLD_MB = int(os.getenv("OOM_KILL_THRESHOLD_MB", "256"))
SEED = int(os.getenv("RANDOM_SEED", str(int(time.time()))))

# ── Global State for Metrics and Simulation ──────────────────────

class AppMetrics:
    """Tracks application metrics."""

    def __init__(self) -> None:
        self.start_time = time.time()
        self.request_count = 0
        self.error_count = 0
        self.total_latency_ms = 0.0
        self.memory_leaked_mb = 0.0
        self.oom_kill_triggered = False
        self._lock = threading.Lock()

    def record_request(self, latency_ms: float, error: bool = False) -> None:
        with self._lock:
            self.request_count += 1
            self.total_latency_ms += latency_ms
            if error:
                self.error_count += 1

    def get_uptime_seconds(self) -> float:
        return time.time() - self.start_time

    def get_avg_latency_ms(self) -> float:
        if self.request_count == 0:
            return 0.0
        return self.total_latency_ms / self.request_count

    def get_error_rate(self) -> float:
        if self.request_count == 0:
            return 0.0
        return (self.error_count / self.request_count) * 100

    def set_oom_kill_triggered(self) -> None:
        with self._lock:
            self.oom_kill_triggered = True

    def to_dict(self) -> dict[str, Any]:
        with self._lock:
            return {
                "uptime_seconds": round(self.get_uptime_seconds(), 2),
                "request_count": self.request_count,
                "error_count": self.error_count,
                "error_rate_percent": round(self.get_error_rate(), 2),
                "avg_latency_ms": round(self.get_avg_latency_ms(), 2),
                "memory_leaked_mb": round(self.memory_leaked_mb, 2),
                "oom_kill_triggered": self.oom_kill_triggered,
            }


metrics = AppMetrics()

# Memory leak state
_memory_store: list[bytes] = []
_leak_task: asyncio.Task[Any] | None = None

# Random state for config-drift simulation
random.seed(SEED)


# ── Failure Mode Simulations ───────────────────────────────────────


async def _memory_leak_task() -> None:
    """Background task that gradually consumes memory (simulating a leak)."""
    logger.info(
        json.dumps({
            "event": "memory_leak_started",
            "leak_rate_mb": LEAK_RATE_MB,
            "failure_mode": FAILURE_MODE,
        })
    )

    while not metrics.oom_kill_triggered:
        try:
            # Allocate memory that won't be garbage collected
            chunk = b"X" * (LEAK_RATE_MB * 1024 * 1024)
            _memory_store.append(chunk)

            current_mb = sum(len(c) for c in _memory_store) / (1024 * 1024)
            metrics.memory_leaked_mb = current_mb

            logger.warning(
                json.dumps({
                    "event": "memory_leak_chunk_allocated",
                    "current_mb": round(current_mb, 2),
                    "chunks": len(_memory_store),
                    "threshold_mb": OOM_KILL_THRESHOLD_MB,
                })
            )

            # Trigger OOMKill simulation if threshold reached
            if current_mb > OOM_KILL_THRESHOLD_MB:
                logger.critical(
                    json.dumps({
                        "event": "oom_kill_threshold_exceeded",
                        "current_mb": round(current_mb, 2),
                        "threshold_mb": OOM_KILL_THRESHOLD_MB,
                    })
                )
                metrics.set_oom_kill_triggered()
                break

            await asyncio.sleep(10)  # Leak every 10 seconds for demo

        except Exception as e:
            logger.error(
                json.dumps({
                    "event": "memory_leak_task_error",
                    "error": str(e),
                })
            )
            break


def _cpu_intensive_work(duration_sec: int = 10) -> float:
    """Simulate CPU-intensive Fibonacci computation."""
    logger.error(
        json.dumps({
            "event": "cpu_spike_started",
            "duration_sec": duration_sec,
        })
    )

    start = time.time()
    result = 0.0

    def fib(n: int) -> int:
        if n <= 1:
            return n
        return fib(n - 1) + fib(n - 2)

    while time.time() - start < duration_sec:
        result = float(fib(20))  # Expensive computation

    elapsed = time.time() - start
    logger.error(
        json.dumps({
            "event": "cpu_spike_completed",
            "elapsed_sec": round(elapsed, 2),
            "result": result,
        })
    )
    return result


async def _cascading_failure_simulation() -> None:
    """Simulate cascading failures across dependent services."""
    logger.error(
        json.dumps({
            "event": "cascading_failure_triggered",
            "dependent_service": "database",
        })
    )
    # Simulate a hanging database connection
    await asyncio.sleep(15)


# ── FastAPI Application ────────────────────────────────────────────

app = FastAPI(
    title="NightOps Demo API",
    version="1.0.0",
    description="Production demo app for TheNightOps incident investigation",
)


@app.on_event("startup")
async def startup_event() -> None:
    """Initialize the application on startup."""
    logger.info(
        json.dumps({
            "event": "app_startup",
            "failure_mode": FAILURE_MODE,
            "version": "1.0.0",
            "environment": {
                "leak_rate_mb": LEAK_RATE_MB,
                "error_rate_percent": ERROR_RATE_PERCENT,
                "cpu_spike_duration_sec": CPU_SPIKE_DURATION_SEC,
                "oom_threshold_mb": OOM_KILL_THRESHOLD_MB,
            },
        })
    )

    # Start background tasks based on failure mode
    global _leak_task

    if FAILURE_MODE == "memory-leak":
        _leak_task = asyncio.create_task(_memory_leak_task())
    elif FAILURE_MODE == "oom-kill":
        _leak_task = asyncio.create_task(_memory_leak_task())


@app.middleware("http")
async def add_metrics_middleware(request: Request, call_next):
    """Track request metrics."""
    start_time = time.time()
    response = None
    error = False

    try:
        response = await call_next(request)
    except Exception as e:
        error = True
        logger.error(
            json.dumps({
                "event": "request_exception",
                "method": request.method,
                "path": request.url.path,
                "error": str(e),
            })
        )
        raise
    finally:
        latency_ms = (time.time() - start_time) * 1000
        if response:
            error = error or response.status_code >= 400
        metrics.record_request(latency_ms, error=error)

    return response


@app.get("/", tags=["service"])
async def root() -> dict[str, Any]:
    """Root endpoint showing service information."""
    return {
        "service": "nightops-demo-api",
        "version": "1.0.0",
        "status": "running",
        "failure_mode": FAILURE_MODE,
        "endpoints": {
            "health": "/healthz",
            "ready": "/readyz",
            "metrics": "/metrics",
            "status": "/api/status",
            "orders": "/api/orders",
            "data": "/api/data",
            "reports": "/api/reports/generate",
            "users": "/api/users",
        },
    }


@app.get("/healthz", tags=["probes"])
async def healthz() -> dict[str, str]:
    """Liveness probe: indicates if the service is alive."""
    return {"status": "alive", "service": "nightops-demo-api"}


@app.get("/readyz", tags=["probes"])
async def readyz() -> dict[str, str]:
    """Readiness probe: indicates if the service is ready to handle traffic."""
    # Fail readiness if memory usage is critical or OOMKill was triggered
    if metrics.oom_kill_triggered:
        logger.error(
            json.dumps({
                "event": "readiness_check_failed",
                "reason": "oom_kill_triggered",
            })
        )
        raise HTTPException(
            status_code=503,
            detail="Service not ready: OOMKill was triggered"
        )

    current_mb = sum(len(c) for c in _memory_store) / (1024 * 1024) if _memory_store else 0
    if current_mb > 200:  # Near typical memory limit
        logger.error(
            json.dumps({
                "event": "readiness_check_failed",
                "reason": "memory_pressure",
                "memory_mb": round(current_mb, 2),
            })
        )
        raise HTTPException(
            status_code=503,
            detail="Service not ready: memory pressure detected"
        )

    return {"status": "ready", "service": "nightops-demo-api"}


@app.get("/metrics", tags=["observability"])
async def metrics_endpoint() -> PlainTextResponse:
    """Prometheus-style metrics endpoint."""
    metrics_dict = metrics.to_dict()

    # Build Prometheus-formatted output
    lines = [
        "# HELP nightops_uptime_seconds Application uptime in seconds",
        "# TYPE nightops_uptime_seconds gauge",
        f"nightops_uptime_seconds {metrics_dict['uptime_seconds']}",
        "",
        "# HELP nightops_requests_total Total HTTP requests",
        "# TYPE nightops_requests_total counter",
        f"nightops_requests_total {metrics_dict['request_count']}",
        "",
        "# HELP nightops_errors_total Total errors",
        "# TYPE nightops_errors_total counter",
        f"nightops_errors_total {metrics_dict['error_count']}",
        "",
        "# HELP nightops_error_rate_percent Error rate percentage",
        "# TYPE nightops_error_rate_percent gauge",
        f"nightops_error_rate_percent {metrics_dict['error_rate_percent']}",
        "",
        "# HELP nightops_latency_ms Average request latency",
        "# TYPE nightops_latency_ms gauge",
        f"nightops_latency_ms {metrics_dict['avg_latency_ms']}",
        "",
        "# HELP nightops_memory_leaked_mb Memory leaked in MB",
        "# TYPE nightops_memory_leaked_mb gauge",
        f"nightops_memory_leaked_mb {metrics_dict['memory_leaked_mb']}",
        "",
    ]

    return PlainTextResponse("\n".join(lines))


@app.get("/api/status", tags=["service"])
async def status() -> dict[str, Any]:
    """Detailed service status endpoint."""
    try:
        process = psutil.Process()
        memory_info = process.memory_info()
        cpu_percent = process.cpu_percent(interval=0.1)
    except Exception:
        memory_info = None
        cpu_percent = 0.0

    metrics_dict = metrics.to_dict()

    return {
        "service": "nightops-demo-api",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "failure_mode": FAILURE_MODE,
        "metrics": metrics_dict,
        "system": {
            "memory_rss_mb": round(memory_info.rss / (1024 * 1024), 2) if memory_info else 0,
            "memory_vms_mb": round(memory_info.vms / (1024 * 1024), 2) if memory_info else 0,
            "cpu_percent": round(cpu_percent, 2),
        },
    }


@app.post("/api/orders", tags=["business-logic"])
async def create_order(order: dict[str, Any] | None = None) -> dict[str, Any]:
    """Process an order with optional failure simulation."""
    order_id = f"order-{int(time.time() * 1000)}"

    logger.info(
        json.dumps({
            "event": "order_received",
            "order_id": order_id,
            "failure_mode": FAILURE_MODE,
        })
    )

    # Simulate work
    await asyncio.sleep(random.uniform(0.1, 0.5))

    # Check if we should fail based on error rate
    if random.randint(1, 100) <= ERROR_RATE_PERCENT:
        logger.error(
            json.dumps({
                "event": "order_processing_failed",
                "order_id": order_id,
                "reason": "simulated_error",
                "error_rate": ERROR_RATE_PERCENT,
            })
        )
        metrics.record_request(100, error=True)
        raise HTTPException(
            status_code=500,
            detail=f"Order processing failed (simulated with {ERROR_RATE_PERCENT}% error rate)"
        )

    logger.info(
        json.dumps({
            "event": "order_processed_successfully",
            "order_id": order_id,
        })
    )

    return {
        "order_id": order_id,
        "status": "created",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/api/data", tags=["data"])
async def get_data() -> dict[str, Any]:
    """Data retrieval endpoint with config-drift simulation."""
    # Config-drift: randomly return incorrect data structure
    if FAILURE_MODE == "config-drift" and random.random() < 0.3:
        logger.warning(
            json.dumps({
                "event": "config_drift_detected",
                "endpoint": "/api/data",
                "returned_wrong_format": True,
            })
        )
        return {"error": "malformed response", "code": 500}

    return {
        "data": [{"id": i, "value": f"item-{i}", "timestamp": datetime.utcnow().isoformat()}
                 for i in range(10)],
        "count": 10,
    }


@app.get("/api/reports/generate", tags=["data"])
async def generate_report() -> dict[str, Any]:
    """Report generation endpoint that can trigger CPU spike."""
    if FAILURE_MODE == "cpu-spike":
        result = _cpu_intensive_work(duration_sec=CPU_SPIKE_DURATION_SEC)
        return {"report": "generated", "computation_result": result}

    return {
        "report": "generated",
        "items": 42,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/api/users", tags=["data"])
async def get_users() -> dict[str, Any]:
    """Users endpoint that can trigger cascading failures."""
    if FAILURE_MODE == "cascading-failure":
        logger.error(
            json.dumps({
                "event": "cascading_failure_start",
                "endpoint": "/api/users",
                "dependent_service": "user_database",
            })
        )
        await _cascading_failure_simulation()
        raise HTTPException(
            status_code=504,
            detail="Database connection timeout (cascading failure)"
        )

    return {
        "users": [
            {"id": 1, "name": "demo-user", "email": "user@example.com"},
            {"id": 2, "name": "test-user", "email": "test@example.com"},
        ],
        "count": 2,
    }


# ── Graceful Shutdown ──────────────────────────────────────────────

@app.on_event("shutdown")
async def shutdown_event() -> None:
    """Cleanup on shutdown."""
    if _leak_task:
        _leak_task.cancel()

    logger.info(
        json.dumps({
            "event": "app_shutdown",
            "final_metrics": metrics.to_dict(),
        })
    )


if __name__ == "__main__":
    uvicorn.run(
        "demo_app:app",
        host="0.0.0.0",
        port=8080,
        log_level="info",
    )
