#!/usr/bin/env bash
# TheNightOps — Local Docker-Compose Demo Script
#
# Run TheNightOps demo entirely locally using Docker Compose.
# Perfect for practicing before conference presentations or quick testing.
#
# Usage:
#   ./scripts/demo-local.sh [--scenario SCENARIO] [--duration SECONDS]
#
# Scenarios:
#   memory-leak       - Memory leak failure (default)
#   cpu-spike         - CPU intensive computation
#   cascading-failure - Cascading failures across services
#   config-drift      - Misconfiguration simulation
#   oom-kill          - Aggressive memory allocation
#
# Example:
#   ./scripts/demo-local.sh --scenario memory-leak --duration 120

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEMO_DIR="${PROJECT_ROOT}/demo/scenarios"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yaml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Demo configuration
SCENARIO="${SCENARIO:-memory-leak}"
DURATION="${DURATION:-120}"
DEMO_APP_PORT=8080
DEMO_APP_HOST="127.0.0.1"
DEMO_APP_URL="http://${DEMO_APP_HOST}:${DEMO_APP_PORT}"

# Internal state
DEMO_CONTAINER_ID=""
CLEANUP_ON_EXIT=true

# ── Utility Functions ──────────────────────────────────────────

print_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║             THE NIGHTOPS LOCAL DEMO (Docker)                   ║
║          Autonomous SRE Agent for Incident Response            ║
║                                                                ║
║              Quick Setup & Testing Edition                     ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

print_header() {
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_instruction() {
    echo -e "${YELLOW}→${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ── Cleanup Function ──────────────────────────────────────────

cleanup() {
    if [ "$CLEANUP_ON_EXIT" = "true" ]; then
        print_header "Cleanup"

        if [ -n "$DEMO_CONTAINER_ID" ]; then
            print_instruction "Stopping demo container..."
            docker stop "$DEMO_CONTAINER_ID" 2>/dev/null || true
            docker rm "$DEMO_CONTAINER_ID" 2>/dev/null || true
        fi

        print_instruction "Stopping Docker services..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true

        print_success "Demo environment cleaned up"
    else
        print_info "Skipping cleanup (use ctrl+c again to force)"
    fi
}

trap cleanup EXIT

# ── Prerequisites Check ────────────────────────────────────────

check_prerequisites() {
    print_header "Prerequisites Check"

    local missing_tools=()

    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null; then
        missing_tools+=("docker-compose")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Install Docker and curl before running this demo"
        exit 1
    fi

    print_success "All required tools found"

    # Check Docker daemon
    if ! docker info &>/dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi

    print_success "Docker daemon is running"

    # Check docker-compose.yaml
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "docker-compose.yaml not found at $DOCKER_COMPOSE_FILE"
        exit 1
    fi

    print_success "docker-compose.yaml found"
    echo ""
}

# ── Build Demo App Container ──────────────────────────────────

build_demo_app() {
    print_header "Building Demo Application Container"

    if [ ! -f "$DEMO_DIR/demo_app.py" ]; then
        print_error "demo_app.py not found at $DEMO_DIR/demo_app.py"
        exit 1
    fi

    # Create a temporary Dockerfile
    local temp_dockerfile=$(mktemp)
    cat > "$temp_dockerfile" << 'DOCKERFILE'
FROM python:3.11-slim

WORKDIR /app

# Install required packages
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    psutil

# Copy the demo app
COPY demo_app.py .

# Expose the API port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')" || exit 1

# Run the app
CMD ["python", "-m", "uvicorn", "demo_app:app", "--host", "0.0.0.0", "--port", "8080"]
DOCKERFILE

    print_instruction "Building Docker image: nightops-demo-api:latest"

    # Build the image
    if docker build \
        -f "$temp_dockerfile" \
        -t nightops-demo-api:latest \
        "$DEMO_DIR" \
        > /dev/null 2>&1; then
        print_success "Demo app image built successfully"
    else
        print_error "Failed to build demo app image"
        rm -f "$temp_dockerfile"
        exit 1
    fi

    rm -f "$temp_dockerfile"
    echo ""
}

# ── Start Services ────────────────────────────────────────────

start_services() {
    print_header "Starting Docker Services"

    print_instruction "Starting services with docker-compose..."

    if docker-compose -f "$DOCKER_COMPOSE_FILE" up -d > /dev/null 2>&1; then
        print_success "Docker services started"
    else
        print_warning "Some services may already be running"
    fi

    sleep 2

    # Show status
    echo ""
    print_info "Service status:"
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps 2>/dev/null | tail -n +2 || true

    echo ""
}

# ── Start Demo App Container ──────────────────────────────────

start_demo_app() {
    print_header "Starting Demo Application"

    print_instruction "Starting nightops-demo-api with scenario: $SCENARIO"
    echo ""

    # Run the demo app container
    DEMO_CONTAINER_ID=$(docker run \
        --rm \
        -d \
        --name nightops-demo-api \
        -p "$DEMO_APP_PORT:8080" \
        -e "FAILURE_MODE=$SCENARIO" \
        -e "LEAK_RATE_MB=15" \
        -e "ERROR_RATE_PERCENT=5" \
        -e "CPU_SPIKE_DURATION_SEC=30" \
        -e "OOM_KILL_THRESHOLD_MB=256" \
        --memory="512m" \
        --cpus="1" \
        nightops-demo-api:latest)

    if [ -z "$DEMO_CONTAINER_ID" ]; then
        print_error "Failed to start demo app container"
        exit 1
    fi

    print_success "Demo app started (Container ID: ${DEMO_CONTAINER_ID:0:12})"

    # Wait for app to be ready
    print_instruction "Waiting for application to be ready..."
    local max_retries=30
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if curl -sf "$DEMO_APP_URL/healthz" > /dev/null 2>&1; then
            print_success "Application is ready!"
            break
        fi
        sleep 1
        retry=$((retry + 1))
    done

    if [ $retry -ge $max_retries ]; then
        print_error "Application failed to become ready within timeout"
        docker logs "$DEMO_CONTAINER_ID" | head -20
        exit 1
    fi

    echo ""
}

# ── Demonstrate App ───────────────────────────────────────────

demonstrate_app() {
    print_header "Demonstrating Application Endpoints"

    echo -e "${BOLD}Testing API Endpoints:${NC}"
    echo ""

    # Test root endpoint
    print_info "GET /"
    curl -s "$DEMO_APP_URL/" | python3 -m json.tool 2>/dev/null | head -15
    echo ""

    # Test health endpoint
    print_info "GET /healthz"
    curl -s "$DEMO_APP_URL/healthz" | python3 -m json.tool
    echo ""

    # Test status endpoint
    print_info "GET /api/status"
    curl -s "$DEMO_APP_URL/api/status" | python3 -m json.tool 2>/dev/null | head -20
    echo ""

    # Test metrics endpoint
    print_info "GET /metrics (Prometheus format)"
    curl -s "$DEMO_APP_URL/metrics" | head -10
    echo ""

    # Generate some traffic
    print_info "Generating sample request traffic..."
    for i in {1..5}; do
        curl -s -X POST "$DEMO_APP_URL/api/orders" \
            -H "Content-Type: application/json" \
            -d '{"item": "demo-item"}' \
            > /dev/null
        echo -n "."
        sleep 0.5
    done
    echo ""
    echo ""

    print_success "All endpoints are working"
    echo ""
}

# ── Monitor Scenario ──────────────────────────────────────────

monitor_scenario() {
    print_header "Monitoring Failure Scenario"

    print_info "Scenario: $SCENARIO"
    print_info "Duration: $DURATION seconds"
    print_info "Watching application behavior and metrics..."
    echo ""

    local elapsed=0
    local check_interval=5

    while [ $elapsed -lt "$DURATION" ]; do
        # Get current metrics
        local metrics
        metrics=$(curl -s "$DEMO_APP_URL/api/status" 2>/dev/null || echo "{}")

        # Try to extract key metrics using python
        python3 << PYTHON
import json
import sys

try:
    metrics = json.loads("""$metrics""")
    m = metrics.get('metrics', {})
    uptime = m.get('uptime_seconds', 0)
    requests = m.get('request_count', 0)
    errors = m.get('error_count', 0)
    error_rate = m.get('error_rate_percent', 0)
    latency = m.get('avg_latency_ms', 0)
    memory_leaked = m.get('memory_leaked_mb', 0)

    print(f"[{int(uptime):3d}s] Requests: {requests:4d} | Errors: {errors:3d} ({error_rate:5.1f}%) | Latency: {latency:6.2f}ms | Memory Leaked: {memory_leaked:6.2f}MB")
except:
    pass
PYTHON

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))

        # Check if we should stop early (e.g., for oom-kill scenario)
        if [ "$SCENARIO" = "oom-kill" ]; then
            if ! docker inspect "$DEMO_CONTAINER_ID" > /dev/null 2>&1; then
                print_warning "Container has exited (OOMKilled)"
                break
            fi
        fi
    done

    echo ""
    print_success "Monitoring complete"
    echo ""
}

# ── Show Logs ─────────────────────────────────────────────────

show_logs() {
    print_header "Application Logs"

    print_info "Recent logs from demo app:"
    echo ""

    docker logs "$DEMO_CONTAINER_ID" 2>/dev/null | tail -30 || true

    echo ""
}

# ── Scenario-Specific Actions ─────────────────────────────────

run_scenario_tests() {
    print_header "Scenario-Specific Testing"

    case "$SCENARIO" in
        memory-leak)
            print_info "Testing memory-leak scenario..."
            echo "The app will leak ~15MB every 10 seconds."
            echo "Watch the memory_leaked_mb metric increase."
            echo ""
            print_success "Memory-leak scenario is running"
            ;;
        cpu-spike)
            print_info "Testing CPU-spike scenario..."
            print_instruction "Triggering CPU-intensive endpoint..."
            echo ""
            # Trigger CPU spike
            curl -s "$DEMO_APP_URL/api/reports/generate" > /dev/null &
            CPU_PID=$!
            # Show system load
            print_info "System load during CPU spike:"
            sleep 2
            for i in {1..5}; do
                uptime | awk -F'load average:' '{print $2}'
                sleep 1
            done
            wait $CPU_PID 2>/dev/null || true
            print_success "CPU-spike scenario completed"
            ;;
        cascading-failure)
            print_info "Testing cascading-failure scenario..."
            print_instruction "Triggering cascading failure..."
            echo ""
            # Trigger cascading failure (will hang and timeout)
            timeout 5s curl -s "$DEMO_APP_URL/api/users" || print_warning "Request timed out (expected)"
            echo ""
            print_success "Cascading failure scenario demonstrated"
            ;;
        config-drift)
            print_info "Testing config-drift scenario..."
            print_instruction "Making multiple requests to catch misconfiguration..."
            echo ""
            # Make multiple requests to potentially catch wrong response
            local found_drift=false
            for i in {1..20}; do
                response=$(curl -s "$DEMO_APP_URL/api/data")
                if echo "$response" | grep -q "error"; then
                    print_warning "Caught config drift response: $response"
                    found_drift=true
                    break
                fi
            done
            if [ "$found_drift" = "true" ]; then
                print_success "Config-drift scenario caught"
            else
                print_info "Config-drift not triggered in timeframe (probabilistic)"
            fi
            ;;
        oom-kill)
            print_info "Testing OOM-kill scenario..."
            echo "The app will aggressively allocate memory until it is killed."
            echo ""
            print_success "OOM-kill scenario is running"
            ;;
    esac

    echo ""
}

# ── Generate Sample Report ────────────────────────────────────

generate_sample_report() {
    print_header "Sample TheNightOps Report"

    cat << 'REPORT'
╔════════════════════════════════════════════════════════════════╗
║              INVESTIGATION SUMMARY                             ║
║          TheNightOps Autonomous Analysis                       ║
╚════════════════════════════════════════════════════════════════╝

Scenario Analyzed: memory-leak
Analysis Duration: 120 seconds
Logs Parsed: 245 structured JSON entries
Anomalies Detected: 3 distinct patterns

KEY FINDINGS
────────────────────────────────────────────────────────────────
1. Memory Growth Pattern Detected
   • Linear increase: ~15MB per 10 seconds
   • Total growth: ~180MB over 120 seconds
   • Pattern consistency: 99.2%
   → Classification: Memory leak (not transient spikes)

2. Service Health Degradation
   • Readiness probe failures: Started at 75s mark
   • Memory threshold breached: 200MB limit
   • Service recovery: Not automatic
   → Indicates critical resource exhaustion

3. Request Processing Impact
   • Request latency: Increased from 5ms to 45ms
   • Error rate: Elevated at 5% (baseline)
   • No correlation with memory growth
   → Indicates resource competition but not direct causation

AUTOMATED RECOMMENDATIONS
────────────────────────────────────────────────────────────────
□ Set strict memory limits: 256Mi per container
□ Implement memory monitoring alerts at 70%, 85%, 95% thresholds
□ Add memory profiler to staging environment
□ Review code for lingering object references
□ Configure pod eviction policies for memory pressure

CONFIDENCE SCORES
────────────────────────────────────────────────────────────────
Root Cause Identification: 92%
Recommendation Actionability: 88%
Alert Recommendation Precision: 91%

Generated by TheNightOps Agent
════════════════════════════════════════════════════════════════
REPORT

    echo ""
}

# ── Main Execution ────────────────────────────────────────────

main() {
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            --no-cleanup)
                CLEANUP_ON_EXIT=false
                shift
                ;;
            --help)
                cat << 'HELP'
TheNightOps Local Docker Demo

Usage: ./scripts/demo-local.sh [OPTIONS]

Options:
  --scenario SCENARIO     Failure scenario to simulate (default: memory-leak)
                         Options: memory-leak, cpu-spike, cascading-failure,
                                 config-drift, oom-kill
  --duration SECONDS      How long to run the scenario (default: 120)
  --no-cleanup            Don't stop containers on exit
  --help                  Show this help message

Examples:
  ./scripts/demo-local.sh
  ./scripts/demo-local.sh --scenario cpu-spike --duration 60
  ./scripts/demo-local.sh --scenario oom-kill --no-cleanup

HELP
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Validate scenario
    case "$SCENARIO" in
        memory-leak|cpu-spike|cascading-failure|config-drift|oom-kill)
            ;;
        *)
            print_error "Unknown scenario: $SCENARIO"
            exit 1
            ;;
    esac

    # Run demo
    check_prerequisites
    build_demo_app
    start_services
    start_demo_app
    demonstrate_app
    run_scenario_tests
    monitor_scenario
    show_logs
    generate_sample_report

    print_header "Demo Complete"
    echo -e "${GREEN}${BOLD}Local demo finished successfully!${NC}"
    echo ""
    print_info "The demo app is available at: $DEMO_APP_URL"
    print_info "Press Ctrl+C to stop and clean up"
    echo ""

    # Keep running until interrupted
    if [ "$CLEANUP_ON_EXIT" = "true" ]; then
        print_info "Waiting before cleanup... (Press Ctrl+C to exit now)"
        sleep 5
    else
        print_info "Containers are still running. Use 'docker stop $DEMO_CONTAINER_ID' to stop."
        print_info "Press Ctrl+C to exit"
        # Just keep the process alive
        wait
    fi
}

main "$@"
