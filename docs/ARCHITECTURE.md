# 📐 Architecture Deep-Dive: kOps Kubernetes Platform on AWS

## 1. Service Exposure Strategy

This project uses **three different Kubernetes service types**, each chosen deliberately:

### Frontend → LoadBalancer (AWS ELB)
- The frontend Apache HTTP server is the **only publicly accessible component**.
- A 	ype: LoadBalancer service causes the Kubernetes cloud-controller-manager to automatically provision an **AWS Elastic Load Balancer (ELB)** and attach it to the frontend pods.
- No Ingress controller is needed — the ELB handles all external traffic routing directly to port 80.
- DNS: Use kubectl get svc frontend-service -n production to get the ELB hostname.

### Backend → ClusterIP (Internal only)
- The Node.js REST API is **never exposed externally**.
- A 	ype: ClusterIP service is assigned a stable virtual IP reachable only within the cluster.
- Frontend pods resolve ackend-service.production.svc.cluster.local via CoreDNS and communicate on port 5000.

### Database → ClusterIP + Headless Service (Internal only)
- MySQL is protected behind two services:
  - mysql-service (ClusterIP): Standard virtual IP for general backend → DB connections.
  - mysql-headless (clusterIP: None): Returns the **direct pod IP** of mysql-0 via DNS — required by StatefulSet for stable identity.
- Backend pods resolve mysql-headless.production.svc.cluster.local directly to the mysql-0 pod.

---

## 2. Why kOps Instead of AWS EKS?
- **Full Control over the Control Plane**: EKS abstracts away the master nodes, etcd, and control plane OS configuration. kOps gives full visibility into:
  - etcd quorum, snapshots, and disaster recovery.
  - Custom API server admission controllers, flags, and feature gates.
  - Customized VPC CIDRs, subnet allocation, and network plugins (Calico).
- **Cost-Efficiency in Sandbox/Training**: Avoids the .10/hour per-cluster AWS EKS management fee when running temporary validation clusters.

---

## 3. StatefulSet vs Deployment for Database Tier
In standard Deployments:
- Pod names are random hashes (e.g. mysql-7b89d44c9-xj82p).
- Replicas are created and destroyed in parallel.
- Volumes are treated as stateless or shared.

In **StatefulSets** (used here for MySQL):
1. **Stable Network Identity**: Pods receive deterministic, zero-indexed ordinals: mysql-0.
2. **Stable Persistent Storage**: Each replica uses a dedicated PVC bound to an AWS EBS Volume via olumeClaimTemplates. When mysql-0 is rescheduled to a new node, AWS automatically detaches the EBS volume from the old node and reattaches it to mysql-0.
3. **Ordered Rollout**: Pod 0 initializes and reaches readiness before Pod 1 starts, preventing database split-brain.

---

## 4. CoreDNS & Headless Service Internal Routing
- A standard Kubernetes ClusterIP Service provides a virtual load-balancing IP.
- A **Headless Service** (clusterIP: None) returns the direct IP addresses of the individual StatefulSet pods via DNS SRV and A records.
- Backend pods resolve mysql-headless.production.svc.cluster.local, which directly yields the active mysql-0 endpoint.

---

## 5. Multi-AZ Fault Tolerance & Anti-Affinity
- Master and worker nodes are split across Availability Zones: us-east-1a and us-east-1b.
- Pod Anti-Affinity rules are configured with 	opologyKey: topology.kubernetes.io/zone, guaranteeing that the scheduler separates backend and frontend pod replicas across distinct AWS failure domains.
- A single AZ outage will not take down the frontend or backend — surviving pods in the other AZ continue serving traffic via the ELB.
