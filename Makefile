# Zero Touch Cluster Makefile

.PHONY: help setup check infra storage cluster system-components monitoring-stack storage-stack deploy-storage deploy-nfs enable-nfs disable-nfs argocd argocd-apps gitops-status gitops-sync status autoinstall-usb cidata-iso cidata-usb usb-list ping restart-node drain-node uncordon-node lint validate logs

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# SSH Key Configuration
SSH_KEY := $(HOME)/.ssh/id_ed25519.pub

##@ Setup & Prerequisites

setup: ## Initial setup - create secrets templates and check prerequisites
	@echo "$(CYAN)Setting up Zero Touch Cluster environment...$(RESET)"
	@if [ ! -f ansible/inventory/secrets.yml ]; then \
		echo "$(YELLOW)Creating secrets.yml from template...$(RESET)"; \
		cp ansible/inventory/secrets.yml.template ansible/inventory/secrets.yml; \
		echo "$(RED)⚠️  Edit ansible/inventory/secrets.yml with your actual values$(RESET)"; \
	fi
	@find kubernetes/system/ -name "values-secret.yaml.template" -exec sh -c \
		'cp "$$1" "$${1%.template}"' _ {} \; 2>/dev/null || true
	@echo "$(GREEN)✅ Setup complete! Edit secret files before proceeding.$(RESET)"

check: ## Check prerequisites and system readiness
	@echo "$(CYAN)Checking prerequisites...$(RESET)"
	@command -v ansible >/dev/null || (echo "$(RED)❌ Ansible not installed$(RESET)" && exit 1)
	@[ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ] || (echo "$(RED)❌ SSH key not found$(RESET)" && exit 1)
	@[ -f ansible/inventory/secrets.yml ] || (echo "$(RED)❌ secrets.yml not found - run 'make setup'$(RESET)" && exit 1)
	@echo "$(GREEN)✅ All prerequisites satisfied$(RESET)"

##@ Infrastructure Deployment

storage: check ## Setup K8s storage server
	@echo "$(CYAN)Deploying K8s storage server...$(RESET)"
	cd ansible && ansible-playbook playbooks/01-k8s-storage-setup.yml

cluster: check ## Setup k3s cluster
	@echo "$(CYAN)Deploying k3s cluster...$(RESET)"
	cd ansible && ansible-playbook playbooks/02-k3s-cluster.yml

infra: storage cluster system-components argocd ## Setup complete infrastructure with GitOps
	@echo "$(GREEN)✅ Complete Zero Touch Cluster infrastructure deployed!$(RESET)"
	@echo "$(CYAN)Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:80$(RESET)"
	@echo "$(CYAN)ArgoCD URL: http://argocd.homelab.local (after DNS setup)$(RESET)"

##@ System Components (Helm Charts)

system-components: monitoring-stack storage-stack ## Deploy all system components
	@echo "$(GREEN)✅ All system components deployed$(RESET)"

monitoring-stack: ## Deploy monitoring stack (Prometheus, Grafana, AlertManager)
	@echo "$(CYAN)Deploying monitoring stack...$(RESET)"
	@if [ ! -f kubernetes/system/monitoring/values-secret.yaml ]; then \
		echo "$(YELLOW)⚠️  Creating values-secret.yaml from template...$(RESET)"; \
		cp kubernetes/system/monitoring/values-secret.yaml.template kubernetes/system/monitoring/values-secret.yaml; \
		echo "$(RED)❗ Edit kubernetes/system/monitoring/values-secret.yaml with your secrets$(RESET)"; \
	fi
	helm dependency update kubernetes/system/monitoring/
	helm upgrade --install monitoring ./kubernetes/system/monitoring \
		--namespace monitoring --create-namespace \
		--values ./kubernetes/system/monitoring/values.yaml \
		--values ./kubernetes/system/monitoring/values-secret.yaml \
		--wait --timeout 10m
	@echo "$(GREEN)✅ Monitoring stack deployed$(RESET)"

storage-stack: ## Deploy storage components (local-path + NFS hybrid)
	@echo "$(CYAN)Deploying storage stack...$(RESET)"
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		--wait --timeout 5m
	@echo "$(GREEN)✅ Storage stack deployed (local-path + NFS)$(RESET)"

##@ Kubernetes (Legacy/Direct)

deploy-storage: ## Verify storage provisioner (local-path included by default)
	@echo "$(CYAN)Verifying storage - using local-path provisioner$(RESET)"
	@kubectl get storageclass
	@echo "$(GREEN)✅ Local storage ready$(RESET)"

deploy-nfs: ## Deploy NFS storage provisioner (requires NFS enabled in Ansible)
	@echo "$(CYAN)Deploying NFS storage provisioner...$(RESET)"
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		--set nfs.enabled=true \
		--wait --timeout 5m
	@echo "$(GREEN)✅ NFS provisioner deployed$(RESET)"
	@echo "$(YELLOW)Note: Ensure NFS is enabled on storage node first$(RESET)"

enable-nfs: ## Enable NFS storage (updates Ansible config and redeploys storage)
	@echo "$(CYAN)Enabling NFS storage...$(RESET)"
	@sed -i 's/nfs_enabled: false/nfs_enabled: true/g' ansible/inventory/group_vars/all.yml
	@echo "$(GREEN)✅ NFS enabled in Ansible configuration$(RESET)"
	@echo "$(CYAN)Re-running storage setup...$(RESET)"
	@cd ansible && ansible-playbook playbooks/01-k8s-storage-setup.yml
	@echo "$(CYAN)Deploying storage stack with NFS...$(RESET)"
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		--set nfs.enabled=true \
		--wait --timeout 5m
	@echo "$(GREEN)✅ NFS storage fully enabled$(RESET)"

disable-nfs: ## Disable NFS storage (updates Ansible config)
	@echo "$(CYAN)Disabling NFS storage...$(RESET)"
	@sed -i 's/nfs_enabled: true/nfs_enabled: false/g' ansible/inventory/group_vars/all.yml
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		--set nfs.enabled=false \
		--wait --timeout 5m
	@echo "$(GREEN)✅ NFS disabled$(RESET)"
	@echo "$(YELLOW)Note: NFS server remains installed but inactive$(RESET)"

##@ GitOps (ArgoCD)

argocd: ## Install and configure ArgoCD
	@echo "$(CYAN)Installing ArgoCD...$(RESET)"
	kubectl apply -k kubernetes/system/argocd/install/
	@echo "$(CYAN)Waiting for ArgoCD to be ready...$(RESET)"
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@if [ -f kubernetes/system/argocd/config/repository-credentials.yaml ]; then \
		echo "$(CYAN)Applying repository credentials...$(RESET)"; \
		kubectl apply -f kubernetes/system/argocd/config/repository-credentials.yaml; \
	else \
		echo "$(YELLOW)⚠️  No repository credentials found. Copy and edit:$(RESET)"; \
		echo "$(YELLOW)   cp kubernetes/system/argocd/config/repository-credentials.yaml.template kubernetes/system/argocd/config/repository-credentials.yaml$(RESET)"; \
	fi
	kubectl apply -f kubernetes/system/argocd/config/argocd-rbac-cm.yaml
	@echo "$(GREEN)✅ ArgoCD installed$(RESET)"
	@echo "$(CYAN)Getting admin password...$(RESET)"
	@ADMIN_PASSWORD=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d); \
	if [ -n "$$ADMIN_PASSWORD" ]; then \
		echo "$(GREEN)ArgoCD admin password: $$ADMIN_PASSWORD$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️  Initial admin secret not found. ArgoCD may still be starting.$(RESET)"; \
	fi

argocd-apps: ## Deploy ArgoCD applications (private workloads)
	@echo "$(CYAN)Deploying ArgoCD applications...$(RESET)"
	@if [ ! -f kubernetes/system/argocd/config/repository-credentials.yaml ]; then \
		echo "$(RED)❌ Repository credentials not found!$(RESET)"; \
		echo "$(YELLOW)Create kubernetes/system/argocd/config/repository-credentials.yaml from template$(RESET)"; \
		exit 1; \
	fi
	kubectl apply -f kubernetes/argocd-apps/
	@echo "$(GREEN)✅ ArgoCD applications deployed$(RESET)"
	@echo "$(CYAN)Check sync status: make gitops-status$(RESET)"

gitops-status: ## Check GitOps application status
	@echo "$(CYAN)ArgoCD Applications:$(RESET)"
	@kubectl get applications -n argocd || echo "$(YELLOW)⚠️  ArgoCD not installed or no applications$(RESET)"
	@echo "\n$(CYAN)Application Health:$(RESET)"
	@kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status" 2>/dev/null || true

gitops-sync: ## Force sync all ArgoCD applications
	@echo "$(CYAN)Syncing all ArgoCD applications...$(RESET)"
	@if command -v argocd >/dev/null 2>&1; then \
		argocd app sync --all; \
	else \
		echo "$(YELLOW)⚠️  ArgoCD CLI not installed. Using kubectl...$(RESET)"; \
		kubectl patch application private-workloads -n argocd --type='merge' -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'; \
	fi
	@echo "$(GREEN)✅ Sync triggered$(RESET)"

##@ Utilities

status: ## Check cluster status
	@echo "$(CYAN)Cluster Status:$(RESET)"
	@kubectl get nodes -o wide || echo "$(RED)❌ kubectl not configured$(RESET)"
	@echo "\n$(CYAN)Storage Classes:$(RESET)"
	@kubectl get storageclass || echo "$(YELLOW)⚠️  No storage classes$(RESET)"
	@echo "\n$(CYAN)Pod Status:$(RESET)"
	@kubectl get pods --all-namespaces | grep -v Running | grep -v Completed || echo "$(GREEN)✅ All pods running$(RESET)"

##@ Autoinstall Provisioning

autoinstall-usb: ## Create autoinstall USB (usage: make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10 [PASSWORD=mypass])
	@if [ -z "$(DEVICE)" ]; then \
		echo "$(RED)❌ Usage: make autoinstall-usb DEVICE=/dev/sdX [HOSTNAME=<name>] [IP_OCTET=<num>] [PASSWORD=<pass>]$(RESET)"; \
		echo "$(YELLOW)💡 Interactive mode: make autoinstall-usb DEVICE=/dev/sdb$(RESET)"; \
		echo "$(YELLOW)💡 Direct mode: make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10$(RESET)"; \
		echo "$(YELLOW)💡 Custom password: make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10 PASSWORD=mypass$(RESET)"; \
		echo "$(YELLOW)💡 Available devices:$(RESET)"; \
		lsblk -d -o NAME,SIZE,TYPE | grep disk 2>/dev/null || echo "No devices found"; \
		exit 1; \
	fi
	@if [ -n "$(HOSTNAME)" ] && [ -n "$(IP_OCTET)" ]; then \
		echo "$(CYAN)Creating autoinstall USB for $(HOSTNAME) (192.168.50.$(IP_OCTET))...$(RESET)"; \
		cd provisioning && ./create-autoinstall-usb.sh -k $(SSH_KEY) $(if $(PASSWORD),-p $(PASSWORD)) $(DEVICE) $(HOSTNAME) $(IP_OCTET); \
	else \
		echo "$(CYAN)Creating autoinstall USB (interactive mode)...$(RESET)"; \
		cd provisioning && ./create-autoinstall-usb.sh -k $(SSH_KEY) $(if $(PASSWORD),-p $(PASSWORD)) $(DEVICE); \
	fi

cidata-iso: ## Create only cloud-init ISO (usage: make cidata-iso HOSTNAME=k3s-master IP_OCTET=10 [PASSWORD=mypass])
	@if [ -z "$(HOSTNAME)" ] || [ -z "$(IP_OCTET)" ]; then \
		echo "$(RED)❌ Usage: make cidata-iso HOSTNAME=<name> IP_OCTET=<num> [PASSWORD=<pass>]$(RESET)"; \
		echo "$(YELLOW)💡 Example: make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11$(RESET)"; \
		echo "$(YELLOW)💡 With password: make cidata-iso HOSTNAME=k3s-worker-01 IP_OCTET=11 PASSWORD=mypass$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Creating cloud-init ISO for $(HOSTNAME) (192.168.50.$(IP_OCTET))...$(RESET)"
	@cd provisioning && ./create-autoinstall-usb.sh --cidata-only -k $(SSH_KEY) $(if $(PASSWORD),-p $(PASSWORD)) $(HOSTNAME) $(IP_OCTET)

cidata-usb: ## Create cidata ISO and write to USB in one step (usage: make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11)
	@if [ -z "$(DEVICE)" ] || [ -z "$(HOSTNAME)" ] || [ -z "$(IP_OCTET)" ]; then \
		echo "$(RED)❌ Usage: make cidata-usb DEVICE=/dev/sdX HOSTNAME=<name> IP_OCTET=<num> [PASSWORD=<pass>]$(RESET)"; \
		echo "$(YELLOW)💡 Example: make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11$(RESET)"; \
		echo "$(YELLOW)💡 With password: make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11 PASSWORD=mypass$(RESET)"; \
		echo "$(YELLOW)💡 Available devices:$(RESET)"; \
		lsblk -d -o NAME,SIZE,TYPE | grep disk 2>/dev/null || echo "No devices found"; \
		exit 1; \
	fi
	@echo "$(CYAN)Creating and writing cidata to USB $(DEVICE) for $(HOSTNAME) (192.168.50.$(IP_OCTET))...$(RESET)"
	@cd provisioning && ./create-autoinstall-usb.sh --cidata-usb $(DEVICE) -k $(SSH_KEY) $(if $(PASSWORD),-p $(PASSWORD)) $(HOSTNAME) $(IP_OCTET)

usb-list: ## List available USB devices
	@echo "$(CYAN)Available block devices:$(RESET)"
	@lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "(NAME|disk)"

##@ Node Management

ping: ## Test connectivity to all nodes
	@echo "$(CYAN)Testing connectivity to all nodes...$(RESET)"
	cd ansible && ansible all_nodes -m ping

restart-node: ## Restart a specific node (usage: make restart-node NODE=k3s-worker-01)
	@if [ -z "$(NODE)" ]; then \
		echo "$(RED)❌ Usage: make restart-node NODE=<node-name>$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Restarting node $(NODE)...$(RESET)"
	cd ansible && ansible $(NODE) -m reboot

drain-node: ## Drain a node for maintenance (usage: make drain-node NODE=k3s-worker-01)
	@if [ -z "$(NODE)" ]; then \
		echo "$(RED)❌ Usage: make drain-node NODE=<node-name>$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Draining node $(NODE)...$(RESET)"
	kubectl drain $(NODE) --ignore-daemonsets --delete-emptydir-data

uncordon-node: ## Uncordon a node after maintenance (usage: make uncordon-node NODE=k3s-worker-01)
	@if [ -z "$(NODE)" ]; then \
		echo "$(RED)❌ Usage: make uncordon-node NODE=<node-name>$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Uncordoning node $(NODE)...$(RESET)"
	kubectl uncordon $(NODE)

##@ Development

lint: ## Lint Ansible playbooks and YAML files
	@echo "$(CYAN)Linting Ansible playbooks...$(RESET)"
	cd ansible && ansible-lint playbooks/ || echo "$(YELLOW)⚠️  ansible-lint not installed$(RESET)"
	@echo "$(CYAN)Linting Kubernetes manifests...$(RESET)"
	@find kubernetes/ -name "*.yaml" -o -name "*.yml" | xargs yamllint || echo "$(YELLOW)⚠️  yamllint not installed$(RESET)"

validate: ## Validate Kubernetes manifests
	@echo "$(CYAN)Validating Kubernetes manifests...$(RESET)"
	@find kubernetes/ -name "*.yaml" -o -name "*.yml" | xargs kubectl apply --dry-run=client -f

##@ Information

logs: ## Show cluster logs (kubectl logs)
	@echo "$(CYAN)Available log commands:$(RESET)"
	@echo "kubectl logs -n kube-system <pod-name>"
	@echo "kubectl get pods --all-namespaces"

##@ Help

help: ## Display this help
	@echo "Zero Touch Cluster - Kubernetes Infrastructure Automation"
	@echo ""
	@echo "Quick Start (Autoinstall):"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10  # Create USB"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb         # Interactive mode"
	@echo "  make infra                                  # Deploy after nodes boot"
	@echo ""
	@echo "Quick Start (Manual):"
	@echo "  make setup      # Initial setup"
	@echo "  make infra      # Deploy infrastructure"
	@echo ""
	@echo "Setup & Prerequisites:"
	@echo "  setup           Create secrets templates and check prerequisites"
	@echo "  check           Check prerequisites and system readiness"
	@echo ""
	@echo "Infrastructure:"
	@echo "  storage         Setup K8s storage server"
	@echo "  cluster         Setup k3s cluster"
	@echo "  infra           Setup complete infrastructure with GitOps"
	@echo ""
	@echo "System Components (Helm):"
	@echo "  system-components       Deploy all system components"
	@echo "  monitoring-stack        Deploy monitoring (Prometheus, Grafana)"
	@echo "  storage-stack           Deploy hybrid storage (local-path + NFS)"
	@echo ""
	@echo "GitOps (ArgoCD):"
	@echo "  argocd          Install and configure ArgoCD"
	@echo "  argocd-apps     Deploy ArgoCD applications"
	@echo "  gitops-status   Check GitOps application status"
	@echo "  gitops-sync     Force sync all applications"
	@echo ""
	@echo "Kubernetes (Legacy):"
	@echo "  deploy-storage  Deploy storage provisioner"
	@echo "  deploy-nfs      Deploy NFS storage provisioner"
	@echo "  enable-nfs      Enable NFS storage"
	@echo "  disable-nfs     Disable NFS storage"
	@echo ""
	@echo "Provisioning:"
	@echo "  autoinstall-usb         Create unattended installation USB"
	@echo "  cidata-iso              Create only cloud-init ISO (no USB required)"
	@echo "  cidata-usb              Create cidata ISO and write to USB (streamlined)"
	@echo "  usb-list                List available USB devices"
	@echo ""
	@echo "Node Management:"
	@echo "  restart-node    Restart a specific node"
	@echo "  drain-node      Drain a node for maintenance"
	@echo "  uncordon-node   Uncordon a node after maintenance"
	@echo ""
	@echo "Development:"
	@echo "  lint            Lint Ansible playbooks and YAML files"
	@echo "  validate        Validate Kubernetes manifests"
	@echo ""
	@echo "Utilities:"
	@echo "  status          Check cluster status"
	@echo "  ping            Test connectivity to all nodes"
	@echo "  logs            Show available log commands"
	@echo ""
	@echo "Examples:"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb  # Interactive mode"
	@echo "  make restart-node NODE=k3s-worker-01"
	@echo "  make drain-node NODE=k3s-master"