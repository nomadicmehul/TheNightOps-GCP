#!/usr/bin/env bash
# TheNightOps — Cleanup Script
# Removes demo resources and optionally deletes the GKE cluster.

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID environment variable}"
CLUSTER_NAME="${CLUSTER_NAME:-nightops-demo}"
ZONE="${GCP_ZONE:-us-central1-a}"

echo "TheNightOps — Cleanup"
echo "====================="

# Remove demo namespace
echo "→ Removing demo namespace..."
kubectl delete namespace nightops-demo --ignore-not-found=true
echo "  ✓ Demo namespace removed"

# Remove container images
echo "→ Removing container images from GCR..."
gcloud container images delete "gcr.io/${PROJECT_ID}/nightops-demo-api:latest" \
    --quiet --force-delete-tags 2>/dev/null || true
echo "  ✓ Images cleaned up"

# Optionally delete cluster
read -p "Delete GKE cluster '${CLUSTER_NAME}'? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "→ Deleting GKE cluster..."
    gcloud container clusters delete "${CLUSTER_NAME}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --quiet
    echo "  ✓ Cluster deleted"
else
    echo "  Cluster preserved."
fi

echo ""
echo "✓ Cleanup complete!"
