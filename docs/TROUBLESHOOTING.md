# 🛠️ L1/L2 Production Kubernetes Troubleshooting Runbook

This runbook documents standard operational triage workflows used when troubleshooting issues on this cluster.

---

### Incident 1: Pod in `CrashLoopBackOff`
**Symptoms**: Pod status displays `CrashLoopBackOff` or `Error`, with restart counts incrementing.
**Diagnosis**:
```bash
# 1. Fetch current status & exit codes
kubectl get pod <pod-name> -n production

# 2. Check pod events and termination reason
kubectl describe pod <pod-name> -n production

# 3. View crash logs from previous container run
kubectl logs <pod-name> -n production --previous
```
**Common Root Causes**:
- Database connection failure (wrong `DB_HOST` or `DB_PASSWORD` in ConfigMap/Secret).
- Application uncaught exception at startup.
- Failed readiness probe timeout.

---

### Incident 2: Pod in `ImagePullBackOff` / `ErrImagePull`
**Symptoms**: Container cannot be scheduled because the image cannot be downloaded.
**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n production | grep -A 10 Events
```
**Common Root Causes**:
- Typo in image repository tag (e.g., `mysql:8.0.35` vs misspelled tag).
- Private registry authentication missing (need `imagePullSecrets`).
- Worker node NAT Gateway / egress route down, preventing internet access to Docker Hub.

---

### Incident 3: PersistentVolumeClaim Stuck in `Pending`
**Symptoms**: MySQL pod stuck in `Pending` with event `FailedScheduling: pod has unbound immediate PersistentVolumeClaims`.
**Diagnosis**:
```bash
kubectl describe pvc mysql-data-mysql-0 -n production
kubectl describe sc
```
**Common Root Causes**:
- AWS EBS CSI driver not installed or instance lacks IAM permissions to attach EBS volumes (`ec2:AttachVolume`, `ec2:CreateVolume`).
- Volume AZ mismatch: Worker node is in `us-east-1a` while PVC was provisioned in `us-east-1b`.

---

### Incident 4: Node in `NotReady`
**Symptoms**: `kubectl get nodes` displays one or more worker nodes in `NotReady`.
**Diagnosis**:
```bash
# 1. Inspect Node conditions
kubectl describe node <node-name>

# 2. SSH into bastion / node and check kubelet service
sudo systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager

# 3. Check disk and memory pressure
df -h
free -m
```
