#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

echo "=========================================================="
echo " Deploying Multi-Tier Production Workloads to Kubernetes"
echo "=========================================================="

echo "[1/6] Applying Production Namespace..."
kubectl apply -f "${K8S_DIR}/00-namespace.yaml"

echo "[2/6] Applying ConfigMaps and Secrets..."
kubectl apply -f "${K8S_DIR}/01-configmap-secret.yaml"

echo "[3/6] Applying MySQL StatefulSet and Headless Service..."
kubectl apply -f "${K8S_DIR}/02-mysql-statefulset.yaml"

echo "[4/6] Applying Node.js Backend API Deployment..."
kubectl apply -f "${K8S_DIR}/03-backend-deployment.yaml"

echo "[5/6] Applying Frontend UI Deployment..."
kubectl apply -f "${K8S_DIR}/04-frontend-deployment.yaml"

echo "[6/6] Applying Ingress Routing Rules..."
kubectl apply -f "${K8S_DIR}/05-ingress.yaml"

echo ""
echo "Waiting for pods to reach Ready status..."
kubectl rollout status statefulset/mysql -n production --timeout=180s || true
kubectl rollout status deployment/backend-api -n production --timeout=120s
kubectl rollout status deployment/frontend-ui -n production --timeout=120s

echo ""
echo "✅ All workloads deployed successfully!"
echo "--- Pods in Namespace 'production' ---"
kubectl get pods -n production -o wide
echo ""
echo "--- Services in Namespace 'production' ---"
kubectl get svc -n production
