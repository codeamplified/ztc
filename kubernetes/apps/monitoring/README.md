# Grafana Monitoring Stack

Complete monitoring solution for the k3s homelab using the kube-prometheus-stack.

## 📊 **What's Deployed**

### **Core Components:**
- **🎨 Grafana**: Web-based visualization and dashboards
- **📈 Prometheus**: Metrics collection and storage  
- **🚨 AlertManager**: Alert routing and management
- **📊 Node Exporter**: Hardware and OS metrics from all nodes
- **🎯 Kube State Metrics**: Kubernetes object metrics
- **⚙️ Prometheus Operator**: Manages Prometheus instances

### **Storage Configuration:**
- **Grafana**: 2Gi NFS persistent storage for dashboards and config
- **Prometheus**: 10Gi NFS persistent storage for metrics data (30-day retention)
- **AlertManager**: 1Gi NFS persistent storage for alert state

## 🌐 **Access URLs**

> **⚠️ DNS Setup Required**: Before accessing these URLs, you must add the domains to your local hosts file. See [DNS Setup](#-dns--hosts-setup) below.

### **Web Interfaces (via Traefik Ingress):**
- **Grafana**: http://grafana.homelab.local
- **Prometheus**: http://prometheus.homelab.local  
- **AlertManager**: http://alertmanager.homelab.local

### **📡 DNS & Hosts Setup**

The `.homelab.local` domains need to resolve to your cluster nodes. Add these entries to your hosts file:

**Linux/macOS**: `/etc/hosts`

```
# Homelab Kubernetes Services
192.168.50.10 grafana.homelab.local
192.168.50.10 prometheus.homelab.local
192.168.50.10 alertmanager.homelab.local
```

**Quick command for Linux/macOS:**
```bash
echo "
# Homelab Kubernetes Services
192.168.50.10 grafana.homelab.local
192.168.50.10 prometheus.homelab.local
192.168.50.10 alertmanager.homelab.local" | sudo tee -a /etc/hosts
```

### **Local Access (Port Forward):**
```bash
# Grafana (primary interface)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
# Access: http://localhost:3000

# Prometheus (metrics and targets)
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Access: http://localhost:9090

# AlertManager (alert management)
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093
# Access: http://localhost:9093
```

## 🔑 **Login Credentials**

### **Grafana:**
- **Username**: `admin`
- **Password**: `pass123` (configured in values-secret.yaml)

*To get the password from Kubernetes secret:*
```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

## 📈 **Pre-Installed Dashboards**

Grafana comes with comprehensive dashboards for k3s monitoring:

### **🏠 Cluster Overview:**
- **Kubernetes / Compute Resources / Cluster**: Overall cluster resource usage
- **Kubernetes / Networking / Cluster**: Network traffic and performance
- **Kubernetes / Storage**: Persistent volume usage across cluster

### **🖥️ Node Monitoring:**
- **Node Exporter / Nodes**: Hardware metrics (CPU, memory, disk, network)
- **Kubernetes / Compute Resources / Node**: Per-node Kubernetes resource usage
- **Node Exporter / USE Method / Node**: Node performance analysis

### **📦 Workload Monitoring:**
- **Kubernetes / Compute Resources / Namespace**: Resource usage by namespace
- **Kubernetes / Compute Resources / Pod**: Individual pod performance
- **Kubernetes / Compute Resources / Workload**: Deployment/StatefulSet metrics

### **⚡ System Monitoring:**
- **Kubernetes / API Server**: Control plane performance
- **Kubernetes / Kubelet**: Node agent performance
- **Prometheus / Overview**: Prometheus server health

## 🎯 **Custom Monitoring Examples**

### **Monitor Custom Applications:**
Create a ServiceMonitor to scrape your app metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-application
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### **Create Custom Alerts:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: monitoring
spec:
  groups:
  - name: my-app.rules
    rules:
    - alert: MyAppDown
      expr: up{job="my-app"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "My application is down"
        description: "My application has been down for more than 5 minutes"
```

## 🔧 **Management Commands**

### **Deployment & Updates:**
```bash
# Deploy monitoring stack
cd kubernetes/apps/monitoring
./deploy.sh

# Update with new values
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values values.yaml \
  --values values-secret.yaml

# Uninstall (⚠️ removes all data)
helm uninstall prometheus-stack -n monitoring
kubectl delete namespace monitoring
```

### **Check Status:**
```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Check persistent volumes
kubectl get pvc -n monitoring

# Check ingress status
kubectl get ingress -n monitoring

# View Grafana logs
kubectl logs -n monitoring deployment/prometheus-stack-grafana
```

### **Backup & Restore:**
```bash
# Backup Grafana dashboards (saved in NFS storage)
kubectl exec -n monitoring deployment/prometheus-stack-grafana -- tar czf - /var/lib/grafana > grafana-backup.tar.gz

# View Prometheus data location (on NFS)
kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -c prometheus -- ls -la /prometheus
```

## 📊 **Monitoring What Matters**

### **🚨 Key Metrics to Watch:**
- **Cluster CPU/Memory Usage**: Should stay under 80% normally
- **Node Disk Space**: Monitor `/` and `/var/lib/rancher/k3s` partitions
- **Pod Restart Count**: High restarts indicate issues
- **Network Traffic**: Unusual spikes may indicate problems

### **⚠️ Default Alerts Include:**
- High CPU/Memory usage on nodes
- Disk space running low
- Pods crash looping
- Kubernetes API server issues
- Node not ready conditions

## 🔍 **Troubleshooting**

### **❌ "404 Not Found" or "Can't Connect" Errors:**

**Problem**: `grafana.homelab.local` returns 404 or connection refused

**Cause**: DNS resolution - your browser can't resolve `.homelab.local` domains

**Solution**: Add domains to your hosts file (see [DNS Setup](#-dns--hosts-setup) above)

**Quick Test:**
```bash
# Test if DNS is working
ping grafana.homelab.local

# Should return: PING grafana.homelab.local (192.168.50.10)...
# If it fails, hosts file setup is needed
```

**Alternative Access (Port Forward):**
```bash
# Direct access without DNS
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3001:80
# Then visit: http://localhost:3001
```

### **Grafana Won't Load:**
```bash
# Check pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check logs
kubectl logs -n monitoring deployment/prometheus-stack-grafana

# Check ingress
kubectl describe ingress prometheus-stack-grafana -n monitoring
```

### **Missing Metrics:**
```bash
# Check Prometheus targets
# Access: http://prometheus.homelab.local/targets
# All targets should be "UP"

# Check ServiceMonitor resources
kubectl get servicemonitor -n monitoring

# Check if metrics endpoints are accessible
kubectl port-forward -n monitoring pod/<node-exporter-pod> 9100:9100
curl http://localhost:9100/metrics
```

### **Storage Issues:**
```bash
# Check NFS mounts
kubectl exec -n monitoring deployment/prometheus-stack-grafana -- df -h

# Check PVC status
kubectl describe pvc -n monitoring

# Test NFS connectivity
kubectl exec -n monitoring deployment/prometheus-stack-grafana -- ping 192.168.50.20
```

## 🏗️ **Architecture Notes**

### **HTTP vs HTTPS Configuration**
This homelab setup uses **HTTP-only** for simplicity:
- ✅ **No TLS certificate management required**
- ✅ **Immediate access without cert errors**
- ✅ **Perfect for private homelab networks**
- ⚠️ **Not recommended for production/public access**

**To enable HTTPS later:**
1. Create TLS certificates (Let's Encrypt, self-signed, etc.)
2. Add `tls:` section back to ingress configurations
3. Update Traefik annotations to include `websecure` entrypoint

## 📁 **Files Structure**

```
monitoring/
├── README.md                    # This documentation
├── deploy.sh                    # Deployment script
├── verify.sh                    # Verification script
├── namespace.yaml               # Monitoring namespace
├── values.yaml                  # Helm chart configuration (HTTP-only ingress)
├── values-secret.yaml           # Secret configuration (not committed)
├── values-secret.yaml.template  # Template for secrets
└── ingress-additional.yaml      # Additional ingress for Prometheus/AlertManager
```

## 🎉 **Next Steps**

1. **Access Grafana**: http://grafana.homelab.local
2. **Explore Dashboards**: Check out the pre-installed Kubernetes dashboards
3. **Set Up Alerts**: Configure AlertManager for email/Slack notifications
4. **Custom Dashboards**: Create dashboards for your specific applications
5. **Monitor Applications**: Add ServiceMonitors for your deployed apps

Your k3s cluster is now comprehensively monitored! 🚀