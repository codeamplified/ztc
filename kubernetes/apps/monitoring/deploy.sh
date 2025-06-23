#!/bin/bash
# Deploy Grafana monitoring stack using Helm

set -e

# Colors for output
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

echo -e "${CYAN}🚀 Deploying Grafana Monitoring Stack${RESET}"

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm is not installed. Please install Helm first.${RESET}"
    echo "Installation: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

# Check if kubectl can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${RESET}"
    exit 1
fi

# Create namespace
echo -e "${CYAN}📦 Creating monitoring namespace...${RESET}"
kubectl apply -f namespace.yaml

# Add Prometheus Community Helm repository
echo -e "${CYAN}📥 Adding Prometheus Community Helm repository...${RESET}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Check if NFS storage class exists
if ! kubectl get storageclass nfs-client &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: nfs-client storage class not found. Using local-path instead.${RESET}"
    # Update values to use local-path
    sed -i 's/storageClassName: nfs-client/storageClassName: local-path/g' values.yaml
fi

# Deploy kube-prometheus-stack
echo -e "${CYAN}🎯 Deploying kube-prometheus-stack...${RESET}"
helm upgrade --install \
    prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values values.yaml \
    --values values-secret.yaml \
    --wait \
    --timeout 10m

echo -e "${GREEN}✅ Monitoring stack deployed successfully!${RESET}"

# Wait for Grafana pod to be ready
echo -e "${CYAN}⏳ Waiting for Grafana to be ready...${RESET}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode)

echo -e "${GREEN}🎉 Deployment Complete!${RESET}"
echo ""
echo -e "${YELLOW}⚠️  DNS Setup Required:${RESET}"
echo -e "Add these entries to your hosts file to access web interfaces:"
echo -e "${CYAN}sudo tee -a /etc/hosts <<EOF"
echo -e "192.168.50.10 grafana.homelab.local"
echo -e "192.168.50.10 prometheus.homelab.local"
echo -e "192.168.50.10 alertmanager.homelab.local"
echo -e "EOF${RESET}"
echo ""
echo -e "${CYAN}📊 Access URLs (after DNS setup):${RESET}"
echo -e "  Grafana: http://grafana.homelab.local"
echo -e "  Prometheus: http://prometheus.homelab.local"
echo -e "  AlertManager: http://alertmanager.homelab.local"
echo -e "  Username: admin"
echo -e "  Password: ${GRAFANA_PASSWORD}"
echo ""
echo -e "${CYAN}🔧 Alternative access (no DNS needed):${RESET}"
echo -e "  kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3001:80"
echo -e "  kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo ""
echo -e "${CYAN}📈 Default dashboards available in Grafana:${RESET}"
echo -e "  • Kubernetes / Compute Resources / Cluster"
echo -e "  • Kubernetes / Compute Resources / Namespace"
echo -e "  • Kubernetes / Compute Resources / Node"
echo -e "  • Node Exporter / Nodes"
echo -e "  • And many more!"