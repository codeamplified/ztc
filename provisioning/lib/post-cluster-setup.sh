#!/bin/bash

# Zero Touch Cluster Post-cluster Setup - Creates Sealed Secrets

# Color codes
CYAN() { echo -e "\033[36m$*\033[0m"; }
GREEN() { echo -e "\033[32m$*\033[0m"; }
YELLOW() { echo -e "\033[33m$*\033[0m"; }
RED() { echo -e "\033[31m$*\033[0m"; }

GREEN "=== Post-cluster Setup: Creating Application Secrets ==="
CYAN "Creating sealed secrets for applications now that cluster is available..."
echo

# Check if sealed-secrets controller is ready
CYAN "Checking sealed-secrets controller availability..."
if ! kubectl get deployment/sealed-secrets-controller -n kube-system >/dev/null 2>&1; then
    RED "❌ Sealed Secrets controller not found. Please install it first:"
    RED "   kubectl apply -f kubernetes/system/sealed-secrets/controller.yaml"
    exit 1
fi

# Wait for controller to be ready
kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=60s
GREEN "✅ Sealed Secrets controller is ready."

# 1. Generate Grafana Secret
GREEN "\n--- Creating Grafana Admin Secret ---"
GRAFANA_PASSWORD=$(openssl rand -base64 16)
YELLOW "Generated Grafana admin password: $GRAFANA_PASSWORD"

# Create monitoring namespace if it doesn't exist
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=$GRAFANA_PASSWORD \
  --namespace=monitoring \
  --dry-run=client -o yaml > /tmp/grafana-secret.yaml

kubeseal --format=yaml < /tmp/grafana-secret.yaml > kubernetes/system/monitoring/values-secret.yaml
rm /tmp/grafana-secret.yaml
GREEN "✅ Grafana admin secret created."

# Apply Grafana sealed secret to cluster
kubectl apply -f kubernetes/system/monitoring/values-secret.yaml
GREEN "✅ Grafana sealed secret applied to cluster."

# 2. Generate Gitea Admin Secret  
GREEN "\n--- Creating Gitea Admin Secret ---"
GITEA_ADMIN_PASSWORD=$(openssl rand -base64 32)
YELLOW "Generated Gitea admin username: ztc-admin"
YELLOW "Generated Gitea admin password: $GITEA_ADMIN_PASSWORD"

# Create gitea namespace if it doesn't exist
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitea-admin-secret \
  --from-literal=username="ztc-admin" \
  --from-literal=password="$GITEA_ADMIN_PASSWORD" \
  --namespace=gitea \
  --dry-run=client -o yaml > /tmp/gitea-admin-secret.yaml

kubeseal --format=yaml < /tmp/gitea-admin-secret.yaml > kubernetes/system/gitea/values-secret.yaml
rm /tmp/gitea-admin-secret.yaml
GREEN "✅ Gitea admin secret created."

# Apply Gitea sealed secret to cluster
kubectl apply -f kubernetes/system/gitea/values-secret.yaml
GREEN "✅ Gitea sealed secret applied to cluster."

# 3. Generate ArgoCD Repository Credentials for Gitea
GREEN "\n--- Creating ArgoCD Repository Credentials ---"
CYAN "Creating repository credentials for ArgoCD to access Gitea..."

# Create argocd namespace if it doesn't exist
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic gitea-repo-credentials \
  --from-literal=type=git \
  --from-literal=url="http://gitea-http.gitea.svc.cluster.local:3000/ztc-admin/workloads.git" \
  --from-literal=username="ztc-admin" \
  --from-literal=password="$GITEA_ADMIN_PASSWORD" \
  --namespace=argocd \
  --dry-run=client -o yaml > /tmp/gitea-repo-credentials.yaml

# Add the ArgoCD repository label
kubectl label --local=true -f /tmp/gitea-repo-credentials.yaml argocd.argoproj.io/secret-type=repository --dry-run=client -o yaml > /tmp/gitea-repo-credentials-labeled.yaml

kubeseal --format=yaml < /tmp/gitea-repo-credentials-labeled.yaml > kubernetes/system/argocd/config/gitea-repository-credentials.yaml
rm /tmp/gitea-repo-credentials.yaml /tmp/gitea-repo-credentials-labeled.yaml
GREEN "✅ ArgoCD repository credentials created."

# Apply ArgoCD repository credentials sealed secret to cluster
kubectl apply -f kubernetes/system/argocd/config/gitea-repository-credentials.yaml
GREEN "✅ ArgoCD repository credentials applied to cluster."

# Wait for sealed secrets controller to process the secrets
CYAN "Waiting for sealed secrets to be processed..."
sleep 10

# Verify secrets are available (check if they exist, not using kubectl wait)
CYAN "Verifying sealed secrets were processed..."
for i in {1..12}; do
    if kubectl get secret grafana-admin-credentials -n monitoring >/dev/null 2>&1 && \
       kubectl get secret gitea-admin-secret -n gitea >/dev/null 2>&1 && \
       kubectl get secret gitea-repo-credentials -n argocd >/dev/null 2>&1; then
        GREEN "✅ All sealed secrets processed and ready."
        break
    else
        if [ $i -eq 12 ]; then
            YELLOW "⚠️  Some secrets may not be ready yet, but continuing..."
        else
            CYAN "Waiting for secrets... (attempt $i/12)"
            sleep 5
        fi
    fi
done

# Note: ArgoCD repository credentials created for workloads repository access
# Workloads repository will be created automatically during post-cluster setup

# 4. Save credentials for user reference
GREEN "\n--- Saving Credentials ---"
cat > credentials.txt <<EOF
# Zero Touch Cluster Credentials
# Generated on: $(date)
# Keep this file secure and delete after noting credentials

## Grafana (Monitoring)
Username: admin
Password: $GRAFANA_PASSWORD
URL: http://grafana.homelab.lan (after deployment)

## Gitea (Git Server)  
Username: ztc-admin
Password: $GITEA_ADMIN_PASSWORD
URL: http://gitea.homelab.lan (after deployment)

## ArgoCD (GitOps)
Username: admin
Password: (get with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
URL: http://argocd.homelab.lan (after deployment)

IMPORTANT: 
- Save these credentials securely
- Delete this file after noting the passwords
- Use 'make backup-secrets' to create encrypted backup
EOF

GREEN "✅ Credentials saved to credentials.txt"
YELLOW "IMPORTANT: Note down the credentials from credentials.txt and delete the file"

GREEN "\n--- Post-cluster Setup Complete! ---"
GREEN "All application secrets created successfully."
echo
CYAN "Next: System components will be deployed, followed by Gitea repository setup."
CYAN "Workload deployments will be ready after 'make infra' completes."