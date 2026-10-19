#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

echo "=========================================================="
echo " Deploying Multi-Tier Production Workloads to Kubernetes"
echo " Architecture: Internet -> AWS ELB -> Frontend (LoadBalancer)"
echo "             -> Backend (ClusterIP) -> MySQL (ClusterIP+Headless)"
echo "=========================================================="

echo "[1/5] Applying Production Namespace..."
kubectl apply -f "${K8S_DIR}/00-namespace.yaml"

echo "[2/5] Applying ConfigMaps and Secrets..."
kubectl apply -f "${K8S_DIR}/01-configmap-secret.yaml"

echo "[3/5] Applying MySQL StatefulSet + Headless Service (ClusterIP internal)..."
kubectl apply -f "${K8S_DIR}/02-mysql-statefulset.yaml"

echo "[4/5] Applying Node.js Backend API Deployment (ClusterIP internal)..."
kubectl apply -f "${K8S_DIR}/03-backend-deployment.yaml"

echo "[5/5] Applying Frontend UI Deployment (LoadBalancer -> AWS ELB)..."
kubectl apply -f "${K8S_DIR}/04-frontend-deployment.yaml"

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
echo ""
echo "--- Frontend Public URL (AWS ELB) ---"
echo "Wait ~60s for ELB to provision, then run:"
echo "  kubectl get svc frontend-service -n production"
echo "  Look for EXTERNAL-IP — that is your AWS ELB DNS hostname"
