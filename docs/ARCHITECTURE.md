# 📐 Architecture Deep-Dive: kOps Kubernetes Platform on AWS

## 1. Why kOps instead of AWS EKS?
- **Full Control over the Control Plane**: EKS abstracts away the master nodes, etcd, and control plane OS configuration. In an enterprise setting or for deep systems mastery, managing the cluster lifecycle via kOps gives full visibility into:
  - etcd quorum, snapshots, and disaster recovery.
  - Custom API server admission controllers, flags, and feature gates.
  - Customized VPC CIDRs, subnet allocation, and network plugins (Calico).
- **Cost-Efficiency in Sandbox/Training**: Avoids the $0.10/hour per-cluster AWS EKS management fee when running temporary validation clusters.

---

## 2. StatefulSet vs Deployment for Database Tier
In standard Deployments:
- Pod names are random hashes (e.g. `mysql-7b89d44c9-xj82p`).
- Replicas are created and destroyed in parallel.
- Volumes are treated as stateless or shared.

In **StatefulSets** (used here for MySQL):
1. **Stable Network Identity**: Pods receive deterministic, zero-indexed ordinals: `mysql-0`, `mysql-1`.
2. **Stable Persistent Storage**: Each replica uses a dedicated PVC bound to an AWS EBS Volume via `volumeClaimTemplates`. When `mysql-0` is rescheduled to a new node, AWS automatically detaches the EBS volume from the old node and reattaches it to `mysql-0`.
3. **Ordered Rollout**: Pod 0 initializes and reaches readiness before Pod 1 starts, preventing database split-brain.

---

## 3. CoreDNS & Headless Service Internal Routing
- A standard Kubernetes ClusterIP Service provides a virtual load-balancing IP.
- A **Headless Service** (`clusterIP: None`) returns the direct IP addresses of the individual StatefulSet pods via DNS SRV and A records.
- Microservices resolve `mysql-headless.production.svc.cluster.local`, which directly yields the active database endpoints.

---

## 4. Multi-AZ Fault Tolerance & Anti-Affinity
- Master and worker nodes are split across Availability Zones: `us-east-1a` and `us-east-1b`.
- Pod Anti-Affinity rules are configured with `topologyKey: "topology.kubernetes.io/zone"`, guaranteeing that the scheduler separates backend and frontend pod replicas across distinct AWS failure domains.
