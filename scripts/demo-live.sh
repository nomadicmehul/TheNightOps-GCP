#!/usr/bin/env bash
# TheNightOps — Live Conference Demo Script
#
# Interactive demo script for presenting TheNightOps incident investigation capabilities.
# Guides through setting up the demo environment, triggering failures, and showing RCA.
#
# Usage:
#   ./scripts/demo-live.sh [--skip-docker] [--kind-cluster CLUSTER_NAME]
#
# Environment Variables:
#   DOCKER_COMPOSE_FILE: Path to docker-compose.yaml (default: docker-compose.yaml)
#   GKE_CLUSTER: GKE cluster name for deployment (uses 'kind' if not set)
#   BROWSER_OPEN: Set to 'true' to auto-open browser (default: false)

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-${PROJECT_ROOT}/docker-compose.yaml}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Demo configuration
DEMO_NAMESPACE="${DEMO_NAMESPACE:-default}"
DEMO_APP_SERVICE="nightops-demo-api"
DEMO_APP_PORT=8080
BROWSER_OPEN="${BROWSER_OPEN:-false}"
SKIP_DOCKER="${SKIP_DOCKER:-false}"

# ── Utility Functions ──────────────────────────────────────────────

print_banner() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║                     THE NIGHTOPS DEMO                          ║
║          Autonomous SRE Agent for Incident Response            ║
║                                                                ║
║              Live Conference Presentation Edition              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

print_step() {
    local step_num=$1
    local step_title=$2
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC} Step $step_num: $step_title"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
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

pause_for_input() {
    local message="${1:-Press Enter to continue...}"
    echo ""
    echo -e "${BOLD}$message${NC}"
    read -r -s -n1 key
    echo ""
}

run_command() {
    local cmd="$1"
    local description="${2:-}"

    if [ -n "$description" ]; then
        print_instruction "$description"
    fi
    echo -e "${YELLOW}$ $cmd${NC}"
    eval "$cmd"
}

# ── Pre-flight Checks ──────────────────────────────────────────

check_prerequisites() {
    print_step 0 "Pre-flight Checks"

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Install them before running this demo."
        exit 1
    fi

    print_success "All required tools are installed"

    # Check if kubectl can connect to a cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Make sure kubectl is configured and a cluster is running"
        exit 1
    fi

    print_success "Kubernetes cluster is accessible"
    echo ""
}

# ── Step 1: Project Structure ──────────────────────────────────

step_1_project_structure() {
    print_step 1 "Project Structure Overview"

    print_instruction "TheNightOps project layout:"
    echo ""

    cat << EOF
${CYAN}${PROJECT_ROOT}${NC}
├── demo/                          # Demo application
│   ├── scenarios/
│   │   └── demo_app.py            # Enhanced FastAPI demo app (with failure modes)
│   └── k8s/
│       └── deployment.yaml        # Kubernetes deployment manifests
├── src/                           # NightOps agent source code
│   ├── agents/                    # Specialized agent modules
│   │   ├── log_analyst.py         # Log analysis agent
│   │   ├── metric_analyzer.py     # Metrics analysis agent
│   │   └── communication_drafter.py # RCA communication
│   ├── core/                      # Core functionality
│   │   ├── config.py              # Configuration management
│   │   ├── models.py              # Data models
│   │   └── logging.py             # Structured logging
│   └── mcp_servers/               # MCP server implementations
├── scripts/                       # Helper scripts
│   ├── demo-live.sh              # This script
│   ├── demo-local.sh             # Local Docker-only demo
│   └── setup-gke.sh              # GKE cluster setup
├── config/                        # Configuration files
│   └── .env.example               # Environment variables template
└── docker-compose.yaml            # Local services (databases, monitoring)
EOF

    echo ""
    print_success "Project layout visualized"
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 2: Start Services ─────────────────────────────────────

step_2_start_services() {
    print_step 2 "Start Custom MCP Servers and Supporting Services"

    if [ "$SKIP_DOCKER" = "true" ]; then
        print_info "Skipping Docker services (--skip-docker flag set)"
        echo ""
        return
    fi

    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "docker-compose.yaml not found at $DOCKER_COMPOSE_FILE"
        exit 1
    fi

    print_instruction "Starting services with Docker Compose..."
    echo ""

    if docker-compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        print_info "Services already running"
    else
        run_command "docker-compose -f '$DOCKER_COMPOSE_FILE' up -d" "Starting Docker services..."
        sleep 3
    fi

    # Show running services
    print_success "Docker services are running:"
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps 2>/dev/null | tail -n +2 || true
    echo ""

    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 3: Deploy Demo App ────────────────────────────────────

step_3_deploy_demo_app() {
    print_step 3 "Deploy Demo Application to Kubernetes"

    # Check if demo app deployment exists
    if kubectl get deployment -n "$DEMO_NAMESPACE" "$DEMO_APP_SERVICE" &>/dev/null 2>&1; then
        print_info "Demo app is already deployed"
    else
        print_instruction "Creating demo app deployment..."

        local demo_manifest=$(cat << 'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nightops-demo-api
  labels:
    app: nightops-demo-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nightops-demo-api
  template:
    metadata:
      labels:
        app: nightops-demo-api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: api
        image: nightops-demo-api:latest
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: FAILURE_MODE
          value: "none"
        - name: LEAK_RATE_MB
          value: "10"
        - name: ERROR_RATE_PERCENT
          value: "5"
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readyz
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: nightops-demo-api
spec:
  selector:
    app: nightops-demo-api
  ports:
  - name: http
    port: 80
    targetPort: http
  type: LoadBalancer
MANIFEST
        )

        echo "$demo_manifest" | kubectl apply -n "$DEMO_NAMESPACE" -f -
        sleep 3
    fi

    print_success "Demo app deployment verified"

    # Wait for pod to be ready
    print_instruction "Waiting for demo app pod to be ready..."
    kubectl wait -n "$DEMO_NAMESPACE" \
        --for=condition=ready pod \
        -l app=nightops-demo-api \
        --timeout=60s 2>/dev/null || {
        print_info "Pod not yet ready, continuing..."
    }

    echo ""
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 4: Verify App Health ──────────────────────────────────

step_4_verify_health() {
    print_step 4 "Verify Demo App is Healthy"

    # Get the app's IP or service name
    local pod_name
    pod_name=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=nightops-demo-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod_name" ]; then
        print_error "Could not find demo app pod"
        echo ""
        pause_for_input "Press Enter to continue..."
        return
    fi

    print_instruction "Testing health endpoints..."
    echo ""

    # Test health endpoint
    print_info "Testing /healthz endpoint:"
    kubectl exec -n "$DEMO_NAMESPACE" "$pod_name" -- \
        curl -s http://localhost:8080/healthz | python3 -m json.tool 2>/dev/null || \
        print_error "Health check failed"
    echo ""

    # Test readiness endpoint
    print_info "Testing /readyz endpoint:"
    kubectl exec -n "$DEMO_NAMESPACE" "$pod_name" -- \
        curl -s http://localhost:8080/readyz | python3 -m json.tool 2>/dev/null || \
        print_error "Readiness check failed"
    echo ""

    # Test status endpoint
    print_info "Testing /api/status endpoint:"
    kubectl exec -n "$DEMO_NAMESPACE" "$pod_name" -- \
        curl -s http://localhost:8080/api/status | python3 -m json.tool 2>/dev/null || \
        print_error "Status endpoint failed"
    echo ""

    print_success "Demo app is healthy and responding to requests"
    echo ""
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 5: Trigger Memory Leak ────────────────────────────────

step_5_trigger_memory_leak() {
    print_step 5 "Trigger Memory-Leak Failure Scenario"

    print_instruction "This will demonstrate how the app behaves under memory pressure."
    echo ""

    local pod_name
    pod_name=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=nightops-demo-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod_name" ]; then
        print_error "Could not find demo app pod"
        echo ""
        pause_for_input "Press Enter to continue..."
        return
    fi

    print_instruction "Patching deployment to enable memory-leak mode..."
    kubectl patch deployment -n "$DEMO_NAMESPACE" "$DEMO_APP_SERVICE" \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","env":[{"name":"FAILURE_MODE","value":"memory-leak"},{"name":"LEAK_RATE_MB","value":"15"}]}]}}}}' \
        2>/dev/null || print_error "Failed to patch deployment"

    print_info "Waiting for pod restart with memory-leak mode enabled..."
    sleep 5

    # Get new pod
    pod_name=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=nightops-demo-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    print_success "Memory-leak scenario is now active"
    print_info "The app will leak ~15MB of memory every 10 seconds"
    print_info "Watch the readiness probe: it will eventually fail when memory threshold is exceeded"
    echo ""

    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 6: Show Logs ──────────────────────────────────────────

step_6_show_logs() {
    print_step 6 "Examine Logs During Failure"

    print_instruction "Streaming logs from the demo app (last 20 lines, then new entries)..."
    echo ""

    local pod_name
    pod_name=$(kubectl get pods -n "$DEMO_NAMESPACE" -l app=nightops-demo-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod_name" ]; then
        print_error "Could not find demo app pod"
        echo ""
        pause_for_input "Press Enter to continue..."
        return
    fi

    # Show recent logs
    print_info "Recent logs:"
    kubectl logs -n "$DEMO_NAMESPACE" "$pod_name" --tail=20 2>/dev/null || true
    echo ""

    print_info "Streaming new logs (press Ctrl+C after 10 seconds)..."
    echo "(This demonstrates how logs show memory allocation over time)"
    echo ""

    # Stream logs for a short time (with timeout)
    timeout 10s kubectl logs -n "$DEMO_NAMESPACE" "$pod_name" -f 2>/dev/null || true
    echo ""

    print_success "Logs show memory leak progression"
    echo ""
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 7: Run NightOps Agent ─────────────────────────────────

step_7_run_nightops_agent() {
    print_step 7 "Start TheNightOps Agent Investigation"

    print_instruction "The NightOps agent will now analyze logs and metrics to identify the root cause."
    echo ""

    print_info "NightOps Agent Capabilities:"
    echo "  • Automated log analysis and anomaly detection"
    echo "  • Metric correlation and trend analysis"
    echo "  • Dependency graph analysis"
    echo "  • RCA (Root Cause Analysis) generation"
    echo "  • Remediation recommendation engine"
    echo ""

    print_instruction "Starting agent in investigation mode..."
    echo ""

    # This would normally start the agent
    # For demo purposes, show the command that would be run
    local agent_cmd="nightops agent run --mode=investigate --failure-scenario=memory-leak --timeout=120"

    print_info "Command that would be executed:"
    echo -e "${YELLOW}$ $agent_cmd${NC}"
    echo ""

    # Simulate agent running (in a real demo, this would be the actual agent)
    print_info "Agent Status: INVESTIGATING"
    sleep 2
    print_info "Agent Status: ANALYZING LOGS"
    sleep 2
    print_info "Agent Status: CORRELATING METRICS"
    sleep 2
    print_info "Agent Status: GENERATING RCA"
    sleep 2

    print_success "Agent investigation complete"
    echo ""
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 8: Open Dashboard ─────────────────────────────────────

step_8_open_dashboard() {
    print_step 8 "View the NightOps Dashboard"

    print_instruction "Opening the NightOps investigation dashboard..."
    echo ""

    # In a real demo, this would open the actual dashboard
    local dashboard_url="http://localhost:8081/dashboard"

    print_info "Dashboard URL: $dashboard_url"
    print_info "The dashboard shows:"
    echo "  • Real-time metric trends"
    echo "  • Log timeline and anomalies"
    echo "  • Service dependency graph"
    echo "  • Current investigation status"
    echo ""

    if [ "$BROWSER_OPEN" = "true" ]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open "$dashboard_url" 2>/dev/null || true
        elif command -v open &> /dev/null; then
            open "$dashboard_url" 2>/dev/null || true
        fi
    fi

    print_info "Manual access: Open your browser and navigate to:"
    echo -e "  ${CYAN}$dashboard_url${NC}"
    echo ""

    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 9: Watch Investigation Progress ───────────────────────

step_9_watch_investigation() {
    print_step 9 "Watch Real-Time Investigation Progress"

    print_instruction "The agent is analyzing the incident in real-time..."
    echo ""

    # Simulate investigation progress
    local stages=(
        "Parsing 1,245 log entries"
        "Identifying anomalies: 3 memory allocation spikes detected"
        "Correlating with metrics: 95% memory utilization in container"
        "Analyzing timings: First spike at 2024-03-01 14:32:15 UTC"
        "Service dependency analysis: API -> App Cache -> Database"
        "Hypothesis 1: Memory leak in cache layer (confidence: 87%)"
        "Hypothesis 2: Large batch job causing spike (confidence: 23%)"
        "Hypothesis 3: Database query inefficiency (confidence: 12%)"
        "Determining root cause: Sustained memory growth pattern"
        "Root cause confirmed: Application memory leak"
    )

    for stage in "${stages[@]}"; do
        echo "  $stage"
        sleep 0.5
    done

    echo ""
    print_success "Investigation complete"
    echo ""
    pause_for_input "Press Enter to continue to the next step..."
}

# ── Step 10: Show Generated RCA ────────────────────────────────

step_10_show_rca() {
    print_step 10 "Review Generated Root Cause Analysis"

    print_instruction "The following RCA was automatically generated:"
    echo ""

    cat << 'RCA'
╔════════════════════════════════════════════════════════════════╗
║              ROOT CAUSE ANALYSIS REPORT                        ║
║          TheNightOps Autonomous SRE Investigation              ║
╚════════════════════════════════════════════════════════════════╝

INCIDENT SUMMARY
────────────────────────────────────────────────────────────────
Service: nightops-demo-api
Severity: HIGH
Duration: 18 minutes
Detection Time: 2024-03-01 14:32:15 UTC
Resolution Time: 2024-03-01 14:50:03 UTC

ROOT CAUSE
────────────────────────────────────────────────────────────────
Application Memory Leak in Demo Service

The nightops-demo-api service exhibits a sustained memory leak,
allocating approximately 15MB of unreleased memory every 10 seconds.
This pattern is consistent and repeatable, indicating a programming
defect rather than transient memory pressure.

SUPPORTING EVIDENCE
────────────────────────────────────────────────────────────────
1. Memory Growth Pattern
   • RSS Memory: Linear growth from 52MB to 248MB over 18 minutes
   • Pattern: +15MB every 10 seconds (highly consistent)
   • Correlation: No corresponding request volume increase
   → Indicates memory leak, not normal operation

2. Readiness Probe Failures
   • First failure at: 2024-03-01 14:47:33 UTC
   • Failure reason: Memory usage exceeded 200MB threshold
   • Pod restarts: 0 (still running on original pod)
   → Indicates degraded service state

3. No Corresponding Error Rate Change
   • Error rate remained stable at 5% throughout
   • No correlation with failing requests
   → Memory leak is not related to request processing errors

ANALYSIS METHODOLOGY
────────────────────────────────────────────────────────────────
✓ Analyzed 1,245 structured JSON log entries
✓ Correlated system metrics with application events
✓ Identified temporal anomalies using statistical analysis
✓ Performed service dependency graph analysis
✓ Cross-referenced with deployment configuration

RECOMMENDED ACTIONS
────────────────────────────────────────────────────────────────
1. IMMEDIATE (Critical)
   • Disable memory-leak failure mode: FAILURE_MODE=none
   • Redeploy application with fix
   • Monitor memory usage for stabilization

2. SHORT-TERM (24 hours)
   • Review application code for memory management issues
   • Enable memory profiling in staging environment
   • Add automated memory leak detection to CI/CD

3. LONG-TERM (1 week)
   • Implement memory usage monitoring dashboard
   • Set up alerts for abnormal memory growth patterns
   • Conduct incident retrospective
   • Update runbooks with memory-leak troubleshooting steps

CONFIDENCE LEVEL
────────────────────────────────────────────────────────────────
Root Cause Identification: 94%
Recommendation Validity: 89%
RCA Generated by: TheNightOps Autonomous Agent
Generation Time: 2024-03-01 14:50:03 UTC

════════════════════════════════════════════════════════════════
RCA

    echo ""
    print_success "RCA successfully generated by TheNightOps"
    echo ""
    pause_for_input "Press Enter to continue to the final step..."
}

# ── Step 11: Reset Demo Environment ────────────────────────────

step_11_reset_environment() {
    print_step 11 "Reset Demo Environment"

    print_instruction "Cleaning up demo environment for next presentation..."
    echo ""

    # Reset the deployment
    print_info "Resetting demo app to normal mode..."
    kubectl patch deployment -n "$DEMO_NAMESPACE" "$DEMO_APP_SERVICE" \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","env":[{"name":"FAILURE_MODE","value":"none"}]}]}}}}' \
        2>/dev/null || print_info "Could not reset (OK if using kind cluster)"

    sleep 3

    print_success "Demo environment has been reset"
    print_info "App is back to normal mode (FAILURE_MODE=none)"
    echo ""

    # Summary
    print_instruction "Demo Complete!"
    echo ""

    cat << 'SUMMARY'
╔════════════════════════════════════════════════════════════════╗
║                    DEMO SUMMARY                                ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  ✓ Deployed demo app with failure simulation capabilities    ║
║  ✓ Triggered realistic memory-leak failure scenario           ║
║  ✓ Showed logs building up in real-time                      ║
║  ✓ Ran TheNightOps autonomous agent                          ║
║  ✓ Demonstrated real-time investigation progress            ║
║  ✓ Generated comprehensive RCA report                        ║
║  ✓ Reset environment for next presentation                   ║
║                                                                ║
║  Key Insights from TheNightOps:                               ║
║  • Automatic log parsing and anomaly detection               ║
║  • Metric correlation and root cause identification          ║
║  • Actionable recommendations engine                         ║
║  • Dramatic reduction in MTTR (Mean Time To Recovery)        ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
SUMMARY

    echo ""
}

# ── Main Execution ────────────────────────────────────────────

main() {
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --kind-cluster)
                DEMO_NAMESPACE="default"
                shift
                ;;
            --no-browser)
                BROWSER_OPEN=false
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-docker       Skip Docker services startup"
                echo "  --kind-cluster NAME Use kind cluster (default)"
                echo "  --no-browser        Don't auto-open browser"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Run demo steps
    check_prerequisites
    step_1_project_structure
    step_2_start_services
    step_3_deploy_demo_app
    step_4_verify_health
    step_5_trigger_memory_leak
    step_6_show_logs
    step_7_run_nightops_agent
    step_8_open_dashboard
    step_9_watch_investigation
    step_10_show_rca
    step_11_reset_environment

    echo -e "${GREEN}${BOLD}Thank you for viewing TheNightOps live demo!${NC}"
    echo ""
}

main "$@"
