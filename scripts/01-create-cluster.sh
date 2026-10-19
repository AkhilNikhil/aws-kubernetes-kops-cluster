#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 01-create-cluster.sh
# Purpose: Automates AWS S3 state store setup and multi-AZ kOps cluster creation
# Author: Akhil B M
# ==============================================================================

CLUSTER_NAME="${NAME:-mycluster.k8s.local}"
STATE_BUCKET="${KOPS_STATE_STORE:-s3://akhil-kops-state-store}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ZONES="${AWS_ZONES:-us-east-1a,us-east-1b}"

echo "=========================================================="
echo " Starting AWS Kubernetes Cluster Provisioning via kOps"
echo " Cluster Name: ${CLUSTER_NAME}"
echo " State Store:  ${STATE_BUCKET}"
echo " Zones:        ${ZONES}"
echo "=========================================================="

# 1. Verify AWS CLI Authentication
echo "[1/5] Verifying AWS Identity..."
aws sts get-caller-identity || {
  echo "Error: AWS credentials not configured. Run 'aws configure' first."
  exit 1
}

# 2. Create S3 State Bucket if not existing
BUCKET_NAME="${STATE_BUCKET#s3://}"
echo "[2/5] Checking S3 state store bucket: ${BUCKET_NAME}..."
if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Creating S3 bucket ${BUCKET_NAME} in region ${AWS_REGION}..."
  if [ "${AWS_REGION}" == "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
  aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled
  echo "Bucket created and versioning enabled."
else
  echo "Bucket ${BUCKET_NAME} already exists."
fi

export KOPS_STATE_STORE="${STATE_BUCKET}"

# 3. Generate kOps Cluster Specification
echo "[3/5] Generating kOps cluster specification..."
kops create cluster \
  --name="${CLUSTER_NAME}" \
  --state="${KOPS_STATE_STORE}" \
  --zones="${ZONES}" \
  --node-count=2 \
  --node-size=t3.medium \
  --master-size=t3.medium \
  --topology=public \
  --networking=calico

# 4. Build Cloud Resources
echo "[4/5] Applying cluster configuration to AWS (creating EC2s, VPC, ASGs, SGs)..."
kops update cluster --name "${CLUSTER_NAME}" --yes --admin

# 5. Validation Loop
echo "[5/5] Polling cluster readiness (this typically takes 5 to 10 minutes)..."
kops validate cluster --wait 10m

echo "✅ Cluster ${CLUSTER_NAME} is fully provisioned and Ready!"
kubectl get nodes -o wide
