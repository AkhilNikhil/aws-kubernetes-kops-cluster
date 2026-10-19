#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${NAME:-mycluster.k8s.local}"
STATE_BUCKET="${KOPS_STATE_STORE:-s3://akhil-kops-state-store}"

export KOPS_STATE_STORE="${STATE_BUCKET}"

echo "=========================================================="
echo " WARNING: INITIATING DESTRUCTION OF CLUSTER: ${CLUSTER_NAME}"
echo "=========================================================="

read -p "Are you sure you want to delete this Kubernetes cluster and all AWS resources? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting cluster resources..."
  kops delete cluster --name="${CLUSTER_NAME}" --yes
  echo "✅ Cluster ${CLUSTER_NAME} deleted from AWS."
else
  echo "Aborted."
fi
