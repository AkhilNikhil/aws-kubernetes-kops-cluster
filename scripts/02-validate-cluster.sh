#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${NAME:-mycluster.k8s.local}"
STATE_BUCKET="${KOPS_STATE_STORE:-s3://akhil-kops-state-store}"

export KOPS_STATE_STORE="${STATE_BUCKET}"

echo "=== [1/4] kOps Cluster Validation ==="
kops validate cluster --name "${CLUSTER_NAME}"

echo ""
echo "=== [2/4] Kubernetes Nodes Status ==="
kubectl get nodes -o wide

echo ""
echo "=== [3/4] Control Plane System Pods ==="
kubectl get pods -n kube-system -o wide

echo ""
echo "=== [4/4] Instance Groups ==="
kops get ig --name "${CLUSTER_NAME}"
