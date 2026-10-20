# 🎬 Video Script: AWS Kubernetes Cluster with kOps
## Full 5-Part Series — Correct Architecture: LoadBalancer + ClusterIP (No Ingress)

> **Architecture:** Internet → AWS ELB → Frontend (LoadBalancer) → Backend (ClusterIP) → MySQL (ClusterIP + Headless)

---

# PART 1: The kOps Foundation
**File: The_kOps_Foundation.mp4 | Runtime: ~10-12 min**

---

## [INTRO — 0:00]
Hey everyone. In this series we are going to walk through a real, production-style Kubernetes cluster I built on AWS using kOps. This is not a tutorial where I just spin up a managed EKS cluster and let AWS handle everything. We are going deeper — we own the entire control plane ourselves.

By the end of this 5-part series you will understand:
- Why we chose kOps over EKS
- How traffic flows through this system — and why we use a LoadBalancer service for the frontend but ClusterIP for everything else
- How StatefulSets work for the database tier
- How CoreDNS and Headless Services handle internal pod communication
- And how to tear it all down without leaving AWS resources burning money

Let us start from the beginning.

---

## [WHAT IS kOps — 1:30]
kOps stands for Kubernetes Operations. It is an open-source CLI that lets you create, upgrade, and manage production-grade Kubernetes clusters on AWS.

Why kOps instead of EKS? With EKS, AWS manages the control plane. You never see master nodes, cannot SSH into the API server, and have very limited control over etcd. You pay 10 cents per hour per cluster just for the management fee.

With kOps, YOU own everything. Master nodes are EC2 instances you can see and SSH into. You configure etcd, set custom API server flags, choose your networking plugin — we use Calico — and tune the operating system. For someone who wants to truly understand Kubernetes internals, kOps is the right choice.

---

## [PROJECT OVERVIEW — 3:00]
Here is what we are building — a three-tier application:

**Tier 1 — Frontend:** Apache HTTP Server, 3 replicas. The ONLY component the internet can reach. Exposed through a Kubernetes **LoadBalancer** service, which auto-provisions an AWS Elastic Load Balancer.

**Tier 2 — Backend:** Node.js REST API, 3 replicas. NEVER exposed to the internet. Only reachable internally via a **ClusterIP** service.

**Tier 3 — Database:** MySQL 8.0, deployed as a **StatefulSet**. Accessible only internally via **ClusterIP** and a **Headless Service**.

I want to be very clear: **We do not use an Ingress controller in this project.** No NGINX Ingress, no AWS ALB Ingress, no Ingress at all. The frontend is directly exposed via a LoadBalancer service and that is it. I will explain exactly why in Part 3.

---

## [PREREQUISITES — 5:00]

**AWS CLI v2:**
```bash
aws --version
aws configure   # Enter Access Key ID, Secret Key, region: us-east-1
```

**kOps CLI:**
```bash
curl -Lo kops https://github.com/kubernetes/kops/releases/download/v1.28.0/kops-linux-amd64
chmod +x kops && sudo mv kops /usr/local/bin/
```

**kubectl:**
```bash
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

---

## [S3 STATE STORE — 7:00]
kOps stores all cluster state — specs, certificates, config — in an Amazon S3 bucket. This is called the State Store.

```bash
aws s3api create-bucket --bucket akhil-kops-state-store --region us-east-1
aws s3api put-bucket-versioning \
    --bucket akhil-kops-state-store \
    --versioning-configuration Status=Enabled

export NAME=mycluster.k8s.local
export KOPS_STATE_STORE=s3://akhil-kops-state-store
```

Every kOps command reads these environment variables to know which cluster and state store to target.

---

## [OUTRO — 10:00]
That is the foundation. In Part 2 we actually provision the cluster — generate the spec, apply it to AWS, and watch kOps create EC2 instances, VPC, subnets, and auto-scaling groups automatically.

---

---

# PART 2: Cluster Lifecycle & Provisioning with kOps
**File: Project_1_Part_2__Cluster_Lifecycle__amp__Provisioning_with_kOp.mp4 | Runtime: ~12-15 min**

---

## [INTRO — 0:00]
In Part 1 we set up the tools and the S3 state store. Now we provision the actual cluster.

---

## [GENERATING THE SPEC — 1:00]
This first command does NOT create anything in AWS yet. It only writes the cluster spec to S3:

```bash
kops create cluster \
  --name=mycluster.k8s.local \
  --state=s3://akhil-kops-state-store \
  --zones=us-east-1a,us-east-1b \
  --node-count=2 \
  --node-size=t3.medium \
  --master-size=t3.medium \
  --topology=public \
  --networking=calico
```

Key flags:
- `--zones=us-east-1a,us-east-1b` — Multi-AZ. If one AZ fails, the other keeps running.
- `--node-count=2` — Two worker nodes, one per AZ.
- `--networking=calico` — Calico CNI for pod networking and NetworkPolicy enforcement.

---

## [APPLYING THE CLUSTER — 3:30]
Now we actually build it on AWS:

```bash
kops update cluster --name mycluster.k8s.local --yes --admin
```

`--yes` confirms you want real AWS resources. `--admin` generates a kubectl kubeconfig with admin credentials.

kOps now creates: VPC, public subnets in both AZs, Internet Gateway, Security Groups, Auto Scaling Groups, EC2 instances (1 master + 2 workers), and IAM roles so nodes can call AWS APIs like EBS attachment and ELB provisioning.

This takes 5-10 minutes.

---

## [VALIDATION — 6:00]
```bash
kops validate cluster --wait 10m
kubectl get nodes -o wide
```

You will see both worker nodes — one in us-east-1a, one in us-east-1b.

---

## [WHAT kOps BUILT — 8:00]
In the AWS Console you will see:
- **EC2:** 1 master + 2 worker instances
- **Auto Scaling Groups:** Separate ASGs for masters and workers — failed nodes are auto-replaced
- **S3:** Full cluster spec, etcd backups, PKI certificates
- **ELB:** kOps creates one ELB for the Kubernetes API server itself

This is the critical difference from EKS — every resource is visible, yours to inspect, and yours to control.

---

## [OUTRO — 11:00]
Cluster is up. In Part 3 we talk about the application architecture — why LoadBalancer for the frontend, ClusterIP for everything else, and how traffic actually moves through the system.

---

---

# PART 3: Resilient Cloud Anatomy
**File: Resilient_Cloud_Anatomy.mp4 | Runtime: ~12 min**

---

## [INTRO — 0:00]
This is the most important video in the series. We are talking about architecture — how traffic flows and why every service type was chosen deliberately.

Starting with the most important point: **We do not use an Ingress controller.** For a straightforward three-tier app on AWS, a LoadBalancer service is simpler, more direct, and perfectly sufficient. No NGINX, no ALB Ingress, nothing extra.

---

## [SERVICE TYPE 1: Frontend → LoadBalancer — 1:30]
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: production
spec:
  type: LoadBalancer        # AWS ELB — exposes frontend publicly
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: frontend-ui
```

When Kubernetes sees `type: LoadBalancer` on AWS, the cloud-controller-manager calls the AWS API and provisions an Elastic Load Balancer automatically. The ELB gets a public DNS hostname. That is your public URL.

**Traffic path: Internet → AWS ELB → frontend pods**

---

## [SERVICE TYPE 2: Backend → ClusterIP — 3:30]
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: production
spec:
  type: ClusterIP           # Internal only — never exposed externally
  ports:
    - port: 5000
      targetPort: 5000
  selector:
    app: backend-api
```

ClusterIP gives the service a stable virtual IP reachable only within the cluster. Frontend pods resolve `backend-service.production.svc.cluster.local` via CoreDNS and talk to the backend on port 5000. Nothing from outside can reach it.

**Traffic path: Frontend pods → backend-service ClusterIP → backend pods**

---

## [SERVICE TYPE 3: Database → ClusterIP + Headless — 5:30]
MySQL has two services:

**mysql-service (ClusterIP):** Standard internal virtual IP for general backend-to-DB connections.

**mysql-headless (clusterIP: None):** Headless service — no virtual IP. DNS returns the actual pod IP of `mysql-0` directly. This is required by the StatefulSet so each pod has a stable, predictable DNS identity.

**Traffic path: Backend pods → mysql-headless → mysql-0 pod directly**

The backend ConfigMap sets:
```yaml
DB_HOST: "mysql-headless.production.svc.cluster.local"
```
This resolves directly to the `mysql-0` pod, every time, regardless of which node it is scheduled on.

---

## [MULTI-AZ RESILIENCE — 8:00]
Frontend and backend both have 3 replicas with Pod Anti-Affinity:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: "topology.kubernetes.io/zone"
```

Pods spread across us-east-1a and us-east-1b. If one AZ goes down, the ELB health checks detect the dead pods and routes only to the surviving AZ. Zero downtime.

---

## [OUTRO — 10:30]
Complete traffic flow: Internet → ELB → Frontend (LoadBalancer) → Backend (ClusterIP) → MySQL (Headless). No Ingress. No NLB. Clean and correct.

Part 4: hardening — resource limits, liveness probes, readiness probes, secrets.

---

---

# PART 4: Bulletproof Kubernetes
**File: Bulletproof_Kubernetes.mp4 | Runtime: ~12 min**

---

## [INTRO — 0:00]
Cluster is running with the correct architecture. Now we make it production-hardened. Three topics: resource limits, health probes, and secrets management.

---

## [RESOURCE LIMITS — 1:00]
Every container has explicit CPU and memory requests and limits:

| Container | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Frontend  | 50m         | 250m      | 64Mi           | 128Mi        |
| Backend   | 100m        | 500m      | 128Mi          | 256Mi        |
| MySQL     | 250m        | 1000m     | 512Mi          | 1Gi          |

**Requests** = what the scheduler reserves on the node.
**Limits** = the maximum the container can consume.

Without limits, a memory leak in one container can OOM-kill the entire node and take down every other pod on it.

---

## [HEALTH PROBES — 4:00]
**Liveness Probe:** Is the container alive? Failure → Kubernetes restarts the container.
**Readiness Probe:** Is the container ready to serve traffic? Failure → Kubernetes removes it from the service endpoint list, stops sending it traffic.

Backend probes (HTTP):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 15
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 5
  periodSeconds: 5
```

MySQL probe (exec — HTTP does not apply to databases):
```yaml
livenessProbe:
  exec:
    command: ["mysqladmin", "ping", "-h", "localhost"]
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

## [SECRETS MANAGEMENT — 8:00]
Credentials are in a Kubernetes Secret, never hardcoded:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: production
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: "ProdSuperAdminPassword2026!"
  MYSQL_USER: "cloudapp_user"
  MYSQL_PASSWORD: "ProdSecureAppPassword2026!"
```

The backend references these via `secretKeyRef`. Credentials are injected at runtime as environment variables — never baked into the image or stored in git.

---

## [ROLLING UPDATES — 10:00]
All deployments use zero-downtime rolling updates:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

`maxUnavailable: 0` — no pod is killed until a new one passes its readiness probe. Zero downtime guaranteed.

---

---

# PART 5: DevOps Incident Triage
**File: DevOps_Incident_Triage.mp4 | Runtime: ~10-12 min**

---

## [INTRO — 0:00]
No cluster runs perfectly forever. This final video walks through the most common production incidents and the exact commands to diagnose and fix them.

---

## [INCIDENT 1: CrashLoopBackOff — 1:00]
```bash
# See the current pod state
kubectl get pods -n production

# Get events and exit codes
kubectl describe pod <pod-name> -n production

# Logs from the previous crashed run
kubectl logs <pod-name> -n production --previous
```

Common causes in this cluster:
- `DB_HOST` wrong in ConfigMap — must be `mysql-headless.production.svc.cluster.local`
- DB password mismatch between Secret and MySQL initialization
- Readiness probe failing before app is ready — check `/health` endpoint

---

## [INCIDENT 2: Frontend ELB Not Accessible — 3:00]
```bash
kubectl get svc frontend-service -n production
```

If `EXTERNAL-IP` shows `<pending>` after 2 minutes:
- The cloud-controller-manager cannot create the ELB — usually IAM permissions. The master node IAM role needs `elasticloadbalancing:*` permissions.

If EXTERNAL-IP is there but browser times out:
- Security group on worker nodes may not allow inbound port 80. Check EC2 → Security Groups in the AWS Console.

---

## [INCIDENT 3: MySQL Stuck in Pending — 5:30]
```bash
kubectl describe pvc mysql-data-mysql-0 -n production
kubectl describe sc
```

Root causes:
- **AWS EBS CSI driver not installed** — storage class cannot provision EBS volumes.
- **AZ mismatch** — PVC provisioned in us-east-1a but pod scheduled on a node in us-east-1b. EBS volumes are AZ-specific. Fix: use a storage class with `volumeBindingMode: WaitForFirstConsumer`.

---

## [INCIDENT 4: Node NotReady — 8:00]
```bash
kubectl get nodes
kubectl describe node <node-name>

# SSH into the node
sudo systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager
df -h     # disk pressure?
free -m   # memory pressure?
```

kOps Auto Scaling Groups auto-replace dead nodes — but you need to understand the root cause.

---

## [TEARDOWN — 10:00]
```bash
./scripts/04-teardown.sh
# Runs: kops delete cluster --name=mycluster.k8s.local --yes
```

kOps deletes all EC2 instances, ASGs, VPC, security groups, and the API server ELB.
The AWS ELB from the frontend LoadBalancer service is also deleted automatically when Kubernetes removes the service.

Optional: delete the S3 state store too:
```bash
aws s3 rb s3://akhil-kops-state-store --force
```

---

## [FINAL OUTRO — 11:30]
That is the complete series. We built a production-grade, multi-AZ Kubernetes cluster on AWS using kOps. Deployed a three-tier application with the correct service types:
- **Frontend** → LoadBalancer (AWS ELB) — public access
- **Backend** → ClusterIP — internal only
- **MySQL** → ClusterIP + Headless — internal only

No Ingress. No NLB. Hardened with resource limits, health probes, and secrets. Incident runbook covered.

This is real DevOps work.

---

# 📋 NotebookLM — Correct Sources to Upload
Replace the wrong sources in your notebook with these files from the repo:

| File | Content |
|------|---------|
| `README.md` | Architecture diagram, traffic flow table, provisioning guide |
| `docs/ARCHITECTURE.md` | Service type decisions deep-dive |
| `docs/TROUBLESHOOTING.md` | Incident runbook (all 4 incidents) |
| `docs/VIDEO_SCRIPT.md` | This file — full narrated script for all 5 videos |

After uploading, **delete the old wrong sources** then regenerate the Audio Overview.
