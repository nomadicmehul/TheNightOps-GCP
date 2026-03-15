#!/usr/bin/env bash
# TheNightOps — Sequential Scenario Test Runner
#
# Runs all 5 demo scenarios against the live GKE cluster using simple mode,
# then verifies pod health, events, and resource usage.
#
# Usage:
#   ./scripts/test-scenarios.sh                  # Run all 5 scenarios + verification
#   ./scripts/test-scenarios.sh --scenario 3     # Run only scenario 3
#   ./scripts/test-scenarios.sh --verify-only    # Skip investigations, just verify
#   ./scripts/test-scenarios.sh --help           # Show usage
#
# Prerequisites:
#   - nightops CLI installed (pip install -e .)
#   - kubectl configured for the target GKE cluster
#   - nightops-demo namespace exists with demo workloads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Defaults ────────────────────────────────────────────────────────
VERIFY_ONLY=false
SCENARIO_NUM=""

# ── Parse Arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --scenario|-s)
            SCENARIO_NUM="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./scripts/test-scenarios.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --scenario, -s N   Run only scenario N (1-5)"
            echo "  --verify-only      Skip investigations, run verification only"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Scenarios:"
            echo "  1  OOMKilled pods in nightops-demo namespace"
            echo "  2  CPU spike on demo-api service"
            echo "  3  Cascading failure / high error rate"
            echo "  4  Config drift causing 500 errors"
            echo "  5  Full cluster health check"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${RESET}"
            echo "Run with --help for usage."
            exit 1
            ;;
    esac
done

# ── Validate --scenario input ──────────────────────────────────────
if [[ -n "${SCENARIO_NUM}" ]] && ! [[ "${SCENARIO_NUM}" =~ ^[1-5]$ ]]; then
    echo -e "${RED}Error: --scenario must be a number between 1 and 5${RESET}"
    exit 1
fi

# ── Scenario Definitions ───────────────────────────────────────────
SCENARIO_NAMES=(
    "OOMKilled Pods"
    "CPU Spike"
    "Cascading Failure"
    "Config Drift"
    "Cluster Health Check"
)

SCENARIO_INCIDENTS=(
    "Pods in the nightops-demo namespace are being OOMKilled. Investigate memory usage, check container resource limits, and identify which pods are affected. Recommend fixes."
    "The demo-api service in nightops-demo namespace is experiencing a CPU spike. Investigate CPU usage across pods, check for hot loops or resource contention, and suggest remediation."
    "High error rate detected across services in nightops-demo namespace — possible cascading failure. Investigate inter-service dependencies, check for failing health probes, and trace the failure chain."
    "The demo-api service is returning HTTP 500 errors after a recent config change. Investigate recent ConfigMap or Secret changes in nightops-demo namespace, check environment variables, and identify the config drift."
    "Perform a full health check of the nightops-demo namespace. Check all pod statuses, pending pods, restart counts, resource pressure, recent warning events, and overall cluster health."
)

# ── Helper Functions ────────────────────────────────────────────────
separator() {
    echo ""
    echo -e "${DIM}$(printf '%.0s─' {1..80})${RESET}"
    echo ""
}

banner() {
    local text="$1"
    echo ""
    echo -e "${BOLD}${BLUE}╔$(printf '%.0s═' {1..78})╗${RESET}"
    printf "${BOLD}${BLUE}║${RESET} ${BOLD}%-76s ${BLUE}║${RESET}\n" "${text}"
    echo -e "${BOLD}${BLUE}╚$(printf '%.0s═' {1..78})╝${RESET}"
    echo ""
}

status_msg() {
    local color="$1"
    local label="$2"
    local msg="$3"
    echo -e "${color}[${label}]${RESET} ${msg}"
}

run_scenario() {
    local num="$1"
    local idx=$((num - 1))
    local name="${SCENARIO_NAMES[$idx]}"
    local incident="${SCENARIO_INCIDENTS[$idx]}"
    local start_time end_time duration

    banner "Scenario ${num}/5: ${name}"

    status_msg "${CYAN}" "START" "Investigating: ${name}"
    echo -e "${DIM}Incident: ${incident}${RESET}"
    echo ""

    start_time=$(date +%s)

    if nightops agent run --simple --incident "${incident}"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo ""
        status_msg "${GREEN}" "DONE" "Scenario ${num} completed in ${duration}s"
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo ""
        status_msg "${YELLOW}" "WARN" "Scenario ${num} exited with non-zero status after ${duration}s"
    fi

    separator
}

run_verification() {
    banner "Verification: Cluster State"

    # Pod health across all namespaces
    status_msg "${CYAN}" "CHECK" "Pod status (all namespaces)"
    echo ""
    kubectl get pods --all-namespaces --no-headers 2>/dev/null | \
        awk '{printf "  %-30s %-40s %-12s %s\n", $1, $2, $3, $4}' || \
        status_msg "${YELLOW}" "SKIP" "kubectl get pods failed (cluster not reachable?)"
    echo ""

    separator

    # Recent events in nightops-demo
    status_msg "${CYAN}" "CHECK" "Recent events in nightops-demo namespace"
    echo ""
    kubectl get events -n nightops-demo --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || \
        status_msg "${YELLOW}" "SKIP" "kubectl get events failed"
    echo ""

    separator

    # Resource usage
    status_msg "${CYAN}" "CHECK" "Resource usage in nightops-demo namespace"
    echo ""
    kubectl top pods -n nightops-demo 2>/dev/null || \
        status_msg "${YELLOW}" "SKIP" "kubectl top pods failed (metrics-server not available?)"
    echo ""
}

# ── Virtual Environment ────────────────────────────────────────────
cd "${PROJECT_ROOT}"

if [[ -d ".venv" ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
elif [[ -d "venv" ]]; then
    # shellcheck disable=SC1091
    source venv/bin/activate
else
    status_msg "${YELLOW}" "WARN" "No virtual environment found — using system Python"
fi

# ── Verify Prerequisites ───────────────────────────────────────────
if ! command -v nightops &>/dev/null; then
    echo -e "${RED}Error: 'nightops' CLI not found. Run: pip install -e .${RESET}"
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}Error: 'kubectl' not found. Install it first.${RESET}"
    exit 1
fi

# ── Main ────────────────────────────────────────────────────────────
banner "TheNightOps — Scenario Test Runner"
echo -e "  ${BOLD}Date:${RESET}    $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "  ${BOLD}Cluster:${RESET} $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo -e "  ${BOLD}Mode:${RESET}    $(if ${VERIFY_ONLY}; then echo 'Verify only'; elif [[ -n "${SCENARIO_NUM}" ]]; then echo "Scenario ${SCENARIO_NUM} only"; else echo 'All scenarios'; fi)"
echo ""

TOTAL_START=$(date +%s)

if [[ "${VERIFY_ONLY}" == "true" ]]; then
    run_verification
elif [[ -n "${SCENARIO_NUM}" ]]; then
    run_scenario "${SCENARIO_NUM}"
    separator
    run_verification
else
    for i in 1 2 3 4 5; do
        run_scenario "${i}"
    done
    run_verification
fi

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

separator
status_msg "${GREEN}" "COMPLETE" "All tasks finished in ${TOTAL_DURATION}s"
echo ""
