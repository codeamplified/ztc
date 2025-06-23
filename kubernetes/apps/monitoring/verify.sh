#!/bin/bash
# Verify Grafana monitoring stack deployment

set -e

# Colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

echo -e "${CYAN}🔍 Verifying Grafana Monitoring Stack${RESET}"

# Check namespace
echo -e "${CYAN}📦 Checking monitoring namespace...${RESET}"
if kubectl get namespace monitoring &> /dev/null; then
    echo -e "${GREEN}✅ Monitoring namespace exists${RESET}"
else
    echo -e "${RED}❌ Monitoring namespace not found${RESET}"
    exit 1
fi

# Check pods
echo -e "${CYAN}🏃 Checking pod status...${RESET}"
kubectl get pods -n monitoring

echo -e "\n${CYAN}📊 Pod readiness summary:${RESET}"
TOTAL_PODS=$(kubectl get pods -n monitoring --no-headers | wc -l)
READY_PODS=$(kubectl get pods -n monitoring --no-headers | grep -c "Running\|Completed" || echo "0")

echo -e "Ready: ${GREEN}${READY_PODS}${RESET} / Total: ${TOTAL_PODS}"

if [ "$READY_PODS" -eq "$TOTAL_PODS" ]; then
    echo -e "${GREEN}✅ All pods are running${RESET}"
else
    echo -e "${YELLOW}⚠️  Some pods are not ready yet${RESET}"
fi

# Check services
echo -e "\n${CYAN}🌐 Checking services...${RESET}"
kubectl get svc -n monitoring

# Check persistent volumes
echo -e "\n${CYAN}💾 Checking persistent storage...${RESET}"
kubectl get pvc -n monitoring

# Check ingress
echo -e "\n${CYAN}🚪 Checking ingress...${RESET}"
kubectl get ingress -n monitoring

# Get Grafana password
echo -e "\n${CYAN}🔑 Grafana credentials:${RESET}"
GRAFANA_PASSWORD=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "Unable to retrieve")
echo -e "Username: ${GREEN}admin${RESET}"
echo -e "Password: ${GREEN}${GRAFANA_PASSWORD}${RESET}"

# Access information
echo -e "\n${CYAN}🌍 Access URLs:${RESET}"
echo -e "Grafana:      http://grafana.homelab.local"
echo -e "Prometheus:   http://prometheus.homelab.local"
echo -e "AlertManager: http://alertmanager.homelab.local"

echo -e "\n${CYAN}🔧 Local access (port-forward):${RESET}"
echo -e "kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80"
echo -e "kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo -e "kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093"

# Quick health check
echo -e "\n${CYAN}🏥 Quick health check...${RESET}"

# Check if Grafana is responding
if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana | grep -q Running; then
    echo -e "${GREEN}✅ Grafana pod is running${RESET}"
else
    echo -e "${RED}❌ Grafana pod is not running${RESET}"
fi

# Check if Prometheus is responding
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus | grep -q Running; then
    echo -e "${GREEN}✅ Prometheus pod is running${RESET}"
else
    echo -e "${RED}❌ Prometheus pod is not running${RESET}"
fi

# Check storage classes
echo -e "\n${CYAN}📁 Storage configuration:${RESET}"
NFS_PVC_COUNT=$(kubectl get pvc -n monitoring -o jsonpath='{.items[*].spec.storageClassName}' | tr ' ' '\n' | grep -c nfs-client || echo "0")
LOCAL_PVC_COUNT=$(kubectl get pvc -n monitoring -o jsonpath='{.items[*].spec.storageClassName}' | tr ' ' '\n' | grep -c local-path || echo "0")

echo -e "NFS storage PVCs: ${GREEN}${NFS_PVC_COUNT}${RESET}"
echo -e "Local-path PVCs: ${GREEN}${LOCAL_PVC_COUNT}${RESET}"

echo -e "\n${GREEN}🎉 Monitoring stack verification complete!${RESET}"
echo -e "${CYAN}Next: Access Grafana at http://grafana.homelab.local${RESET}"