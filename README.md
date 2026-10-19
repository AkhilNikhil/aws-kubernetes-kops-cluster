# ☸️ Production AWS Kubernetes Cluster via kOps
## High-Availability Multi-Tier Microservices Infrastructure on AWS EC2

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.28-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20S3%20%7C%20EBS%20%7C%20ELB-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![kOps](https://img.shields.io/badge/kOps-v1.28-326CE5)](https://kops.sigs.k8s.io/)
[![Architecture](https://img.shields.io/badge/Architecture-Multi--AZ%20HA-brightgreen)](#system-architecture)

---

## 📌 Executive Summary

This repository contains the complete infrastructure code, Kubernetes manifests, and operational automation for provisioning and operating an enterprise-grade, highly available Kubernetes cluster on **Amazon Web Services (AWS)** using **kOps (Kubernetes Operations)**.

The cluster hosts a multi-tier microservices application:
1. **Frontend Tier**: 3 Replicas of containerized Web UI (Apache HTTP Server) exposed publicly via a Kubernetes **LoadBalancer Service** (backed by an AWS ELB).
2. **Backend API Tier**: 3 Replicas of Node.js REST API accessible **only internally** via **ClusterIP** service — reachable from the frontend using CoreDNS.
3. **Database Tier**: Stateful MySQL 8.0 deployed via **Kubernetes StatefulSet (mysql-0)** with persistent AWS EBS storage, accessible **only internally** via **ClusterIP** and a **Headless Service** for direct pod DNS resolution.

> **No Ingress controller is used.** Traffic flows: Internet → AWS ELB → Frontend (LoadBalancer) → Backend (ClusterIP) → MySQL (ClusterIP + Headless).

---

## 🏛️ System Architecture

`mermaid
flowchart TD
    Client([🌐 Internet / Clients]) --> ELB[AWS Elastic Load Balancer\n(Auto-provisioned by K8s LoadBalancer Service)]

    subgraph VPC [AWS VPC (Multi-AZ: us-east-1a / us-east-1b)]

        subgraph K8s [kOps Kubernetes Cluster]

            ELB --> FeSvc[frontend-service\n(Type: LoadBalancer | Port 80)]

            subgraph FeTier [Frontend Tier — Apache HTTP Server (3 Replicas)]
                FeSvc --> PodF1[frontend-pod-1\n(us-east-1a)]
                FeSvc --> PodF2[frontend-pod-2\n(us-east-1b)]
                FeSvc --> PodF3[frontend-pod-3\n(us-east-1a)]
            end

            PodF1 & PodF2 & PodF3 --> BeSvc[backend-service\n(Type: ClusterIP | Port 5000)]

            subgraph BeTier [Backend API Tier — Node.js REST (3 Replicas)]
                BeSvc --> PodB1[backend-api-1]
                BeSvc --> PodB2[backend-api-2]
                BeSvc --> PodB3[backend-api-3]
            end

            PodB1 & PodB2 & PodB3 --> DbSvc[mysql-headless\n(Headless Service | Port 3306)]

            subgraph DbTier [Database Tier — MySQL 8.0 StatefulSet]
                DbSvc --> DbPod0[mysql-0\n(StatefulSet Pod)]
            end
        end

        subgraph Storage [AWS Persistent Storage]
            DbPod0 -.-> EBS0[(AWS EBS Volume\n(PVC: mysql-data-mysql-0 | 10Gi gp3))]
        end

        subgraph StateStore [kOps State Store]
            S3[(Amazon S3\ns3://akhil-kops-state-store)]
        end
    end
`

---

## 🔗 Traffic Flow Summary

| Hop | From | To | Service Type | Protocol |
|:----|:-----|:---|:-------------|:---------|
| 1 | Internet | AWS ELB | — | HTTP :80 |
| 2 | AWS ELB | Frontend Pods | **LoadBalancer** | HTTP :80 |
| 3 | Frontend Pods | Backend Pods | **ClusterIP** | HTTP :5000 |
| 4 | Backend Pods | MySQL Pod | **ClusterIP + Headless** | TCP :3306 |

---

## 📂 Repository Layout

`	ext
aws-kubernetes-kops-cluster/
├── README.md                           # Master project guide & architecture
├── docs/
│   ├── ARCHITECTURE.md                 # Deep-dive architectural design decisions
│   └── TROUBLESHOOTING.md              # L1/L2 Production incident runbook
├── k8s/
│   ├── 00-namespace.yaml               # Isolated production namespace
│   ├── 01-configmap-secret.yaml        # Externalized configs & Base64 secrets
│   ├── 02-mysql-statefulset.yaml       # MySQL StatefulSet + Headless Service + EBS PVC
│   ├── 03-backend-deployment.yaml      # Node.js API Deployment (3 Replicas) + ClusterIP
│   └── 04-frontend-deployment.yaml     # Apache HTTP Deployment (3 Replicas) + LoadBalancer
├── scripts/
│   ├── 01-create-cluster.sh            # Automated kOps cluster provisioning
│   ├── 02-validate-cluster.sh          # Readiness verification & node health check
│   ├── 03-deploy-workloads.sh          # Ordered manifest deployment
│   └── 04-teardown.sh                  # Clean cluster destruction
└── video-explanations/
    ├── README.md                        # Video index
    ├── The_kOps_Foundation.mp4
    ├── Project_1_Part_2__Cluster_Lifecycle__amp__Provisioning_with_kOp.mp4
    ├── Resilient_Cloud_Anatomy.mp4
    ├── Bulletproof_Kubernetes.mp4
    └── DevOps_Incident_Triage.mp4
`

---

## ⚡ Step-by-Step Provisioning Guide

### 1. Prerequisites & Tooling
Ensure your bastion operator machine has the required binaries:
`ash
# AWS CLI v2
aws --version

# kOps CLI
curl -Lo kops https://github.com/kubernetes/kops/releases/download/v1.28.0/kops-linux-amd64
chmod +x kops && sudo mv kops /usr/local/bin/

# kubectl
curl -LO https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
`

### 2. S3 State Store & Environment Variables
kOps stores complete cluster state, certificates, and specifications in Amazon S3:
`ash
aws s3api create-bucket \
    --bucket akhil-kops-state-store \
    --region us-east-1

aws s3api put-bucket-versioning \
    --bucket akhil-kops-state-store \
    --versioning-configuration Status=Enabled

export NAME=mycluster.k8s.local
export KOPS_STATE_STORE=s3://akhil-kops-state-store
`

### 3. Generate Cluster Configuration
`ash
kops create cluster \
    --name= \
    --state= \
    --zones=us-east-1a,us-east-1b \
    --node-count=2 \
    --node-size=t3.medium \
    --master-size=t3.medium \
    --topology=public \
    --networking=calico
`

### 4. Build and Launch Infrastructure
`ash
kops update cluster --name  --yes --admin
kops validate cluster --wait 10m
`

### 5. Deploy Multi-Tier Applications
`ash
chmod +x scripts/*.sh
./scripts/03-deploy-workloads.sh
`

### 6. Get the Frontend Public URL
Once deployed, get the AWS ELB DNS name assigned to the frontend LoadBalancer service:
`ash
kubectl get svc frontend-service -n production
# EXTERNAL-IP will show the AWS ELB hostname (e.g. a1b2c3d4.us-east-1.elb.amazonaws.com)
`

---

## 🎯 Key Architectural Decisions

| Decision | Implementation | Why |
| :--- | :--- | :--- |
| **Frontend Exposure** | **LoadBalancer Service** (AWS ELB) | Direct K8s-native way to expose a service publicly on AWS without an Ingress controller. ELB auto-provisioned by cloud-controller-manager. |
| **Backend Isolation** | **ClusterIP** | Backend must never be publicly accessible. Only reachable internally via CoreDNS from frontend pods. |
| **Database Isolation** | **ClusterIP + Headless Service** | MySQL is strictly internal. Headless service provides stable DNS for StatefulSet pod (mysql-0) direct addressing. |
| **Cluster Orchestration** | **kOps** | Full transparency into control-plane topology, etcd clustering, and OS-level tuning on AWS. |
| **Database Workloads** | **StatefulSet** | Stable persistent network identity (mysql-0), predictable boot ordering, and dedicated EBS volume binding. |
| **Storage Persistence** | **AWS EBS gp3** | 3,000 IOPS baseline, fast MySQL I/O, and automatic re-attachment when pods reschedule across nodes. |
| **High Availability** | **Multi-AZ + Anti-Affinity** | Pods spread across us-east-1a and us-east-1b — AZ failure does not take down the service. |

---

## 🔍 Day-2 Operations & Verification

`ash
# Cluster health
kops validate cluster

# All pods in production namespace
kubectl get pods -n production -o wide

# Check services and ELB external IP
kubectl get svc -n production

# Check Persistent Volume Claims
kubectl get pvc,pv -n production

# Test backend reachability from a frontend pod
kubectl exec -it <frontend-pod> -n production -- curl http://backend-service:5000/health

# Test DB reachability from a backend pod
kubectl exec -it <backend-pod> -n production -- nslookup mysql-headless
`

---

## 🧹 Tear Down
`ash
./scripts/04-teardown.sh
`
