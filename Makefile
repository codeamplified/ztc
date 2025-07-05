# Zero Touch Cluster Makefile

.PHONY: help setup check infra storage cluster deploy-dns dns-status copy-kubeconfig post-cluster-setup system-components monitoring-stack storage-stack setup-gitea-repos deploy-storage deploy-nfs enable-nfs disable-nfs argocd argocd-apps gitops-status gitops-sync status autoinstall-usb cidata-iso cidata-usb usb-list ping restart-node drain-node uncordon-node lint validate teardown logs undeploy-workload undeploy-n8n undeploy-uptime-kuma undeploy-homepage undeploy-vaultwarden undeploy-code-server

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

setup: ## Interactive wizard to set up secrets and prerequisites
	@chmod +x provisioning/lib/setup-wizard.sh
	@./provisioning/lib/setup-wizard.sh

trust-hosts: ## Scan and trust SSH host keys for all nodes in the inventory
	@echo "$(CYAN)Scanning and trusting SSH host keys...$(RESET)"
	@ansible-inventory -i ansible/inventory/hosts.ini --list | \
		grep -oE '"ansible_host": "([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})"' | \
		cut -d '"' -f 4 | \
		xargs -I {} ssh-keyscan -H {} >> ~/.ssh/known_hosts
	@echo "$(GREEN)✅ SSH host keys trusted.$(RESET)"

backup-secrets: ## Backup all critical secrets to an encrypted archive
	@echo "$(CYAN)Backing up secrets...$(RESET)"
	@if [ ! -f .ansible-vault-password ]; then \
		echo "$(RED)❌ Ansible Vault password file not found. Run 'make setup' first.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Auto-generating secure backup password...$(RESET)"
	@BACKUP_PASSWORD=$$(openssl rand -base64 32); \
	echo "$(YELLOW)Backup password: $$BACKUP_PASSWORD$(RESET)"; \
	echo "$(YELLOW)Save this password - you'll need it to recover secrets!$(RESET)"; \
	kubectl get secret -n kube-system $$(kubectl get secrets -n kube-system -o name | grep sealed-secrets-key | head -1 | cut -d'/' -f2) -o yaml > /tmp/sealed-secrets-key.yaml; \
	tar -czf - \
		.ansible-vault-password \
		ansible/inventory/secrets.yml \
		/tmp/sealed-secrets-key.yaml \
		| gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$$BACKUP_PASSWORD" -o ztc-secrets-backup-$(shell date +%Y-%m-%d).tar.gz.gpg; \
	rm -f /tmp/sealed-secrets-key.yaml
	@echo "$(GREEN)✅ Secrets backup created: ztc-secrets-backup-$(shell date +%Y-%m-%d).tar.gz.gpg$(RESET)"
	@echo "$(YELLOW)ACTION REQUIRED: Copy this file to a safe, offline location.$(RESET)"

recover-secrets: ## Recover secrets from an encrypted archive
	@echo "$(CYAN)Recovering secrets...$(RESET)"
	@echo "$(CYAN)Enter the path to your backup file:$(RESET)"
	@read BACKUP_FILE; \
	if [ ! -f "$BACKUP_FILE" ]; then \
		echo "$(RED)❌ Backup file not found.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)Enter the password for the backup archive:$(RESET)"
	@read -s BACKUP_PASSWORD; \
	gpg --decrypt --batch --yes --passphrase "$BACKUP_PASSWORD" "$BACKUP_FILE" | tar -xzf -
	@kubectl apply -f <(kubectl get secret -n kube-system sealed-secrets-key -o yaml)
	@echo "$(GREEN)✅ Secrets recovered successfully.$(RESET)"


copy-kubeconfig: ## Copy kubeconfig from master node to local kubectl config
	@echo "$(CYAN)Setting up kubectl configuration...$(RESET)"
	@if [ -f ~/.kube/k3s-master-config ]; then \
		cp ~/.kube/k3s-master-config ~/.kube/config; \
		echo "$(GREEN)✅ Kubeconfig copied to ~/.kube/config$(RESET)"; \
	else \
		echo "$(RED)❌ Kubeconfig not found. Cluster deployment may have failed.$(RESET)"; \
		exit 1; \
	fi

post-cluster-setup: ## Create sealed secrets for applications
	@echo "$(CYAN)Creating application sealed secrets...$(RESET)"
	@chmod +x provisioning/lib/post-cluster-setup.sh
	@./provisioning/lib/post-cluster-setup.sh

##@ Infrastructure Deployment

storage: check ## Setup K8s storage server
	@echo "$(CYAN)Deploying K8s storage server...$(RESET)"
	cd ansible && ansible-playbook playbooks/01-k8s-storage-setup.yml

cluster: check ## Setup k3s cluster
	@echo "$(CYAN)Deploying k3s cluster...$(RESET)"
	cd ansible && ansible-playbook playbooks/02-k3s-cluster.yml

deploy-dns: check ## Deploy DNS server for homelab services
	@echo "$(CYAN)Deploying DNS server on storage node...$(RESET)"
	cd ansible && ansible-playbook playbooks/03-dns-server.yml
	@echo "$(GREEN)✅ DNS server deployed$(RESET)"
	@echo "$(YELLOW)📋 Configure your router to use 192.168.50.20 as DNS server$(RESET)"

dns-status: ## Check DNS server status and health
	@echo "$(CYAN)Checking DNS server status...$(RESET)"
	@if ssh -o ConnectTimeout=5 ubuntu@192.168.50.20 'systemctl is-active --quiet dnsmasq' 2>/dev/null; then \
		echo "$(GREEN)✅ DNS service is running$(RESET)"; \
		echo "$(CYAN)Running health check...$(RESET)"; \
		ssh ubuntu@192.168.50.20 'sudo /usr/local/bin/dns-health-check.sh' || echo "$(YELLOW)⚠️  Health check script not found$(RESET)"; \
	else \
		echo "$(RED)❌ DNS service is not running or storage node unreachable$(RESET)"; \
	fi

infra: storage cluster copy-kubeconfig install-sealed-secrets post-cluster-setup deploy-dns system-components setup-gitea-repos argocd ## Setup complete infrastructure with GitOps
	@echo "$(GREEN)✅ Complete Zero Touch Cluster infrastructure deployed!$(RESET)"
	@echo "$(CYAN)Check credentials in credentials.txt file$(RESET)"
	@echo "$(CYAN)Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:80$(RESET)"
	@echo "$(CYAN)ArgoCD URL: http://argocd.homelab.lan (after DNS setup)$(RESET)"
	@echo "$(YELLOW)📋 Next Steps:$(RESET)"
	@echo "  1. Configure your router to use 192.168.50.20 as DNS server"
	@echo "  2. Test: curl http://argocd.homelab.lan"
	@echo "  3. Documentation: see docs/dns-setup.md"

##@ System Components (Helm Charts)

system-components: monitoring-stack storage-stack gitea-stack ## Deploy all system components
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

gitea-stack: ## Deploy Gitea Git server for private workloads
	@echo "$(CYAN)Deploying Gitea Git server...$(RESET)"
	@if [ ! -f kubernetes/system/gitea/values-secret.yaml ]; then \
		echo "$(YELLOW)⚠️  Creating values-secret.yaml from template...$(RESET)"; \
		cp kubernetes/system/gitea/values-secret.yaml.template kubernetes/system/gitea/values-secret.yaml; \
		echo "$(RED)❗ Run 'make setup' to generate proper SealedSecret for Gitea admin$(RESET)"; \
	fi
	@echo "$(CYAN)Updating Helm dependencies...$(RESET)"
	helm dependency update kubernetes/system/gitea/
	@echo "$(CYAN)Installing Gitea (this may take 2-3 minutes)...$(RESET)"
	helm upgrade --install gitea ./kubernetes/system/gitea \
		--namespace gitea --create-namespace \
		--values ./kubernetes/system/gitea/values.yaml \
		--wait --timeout 15m
	@echo "$(GREEN)✅ Gitea Git server deployed$(RESET)"
	@echo "$(CYAN)Access Gitea UI: http://gitea.homelab.lan$(RESET)"
	@echo "$(CYAN)SSH clone: git clone git@gitea.homelab.lan:30022/user/repo.git$(RESET)"
	@echo "$(YELLOW)Default admin: ztc-admin / changeme123 (change after first login)$(RESET)"

setup-gitea-repos: ## Setup required Gitea repositories after deployment
	@echo "$(CYAN)Setting up Gitea repositories...$(RESET)"
	@chmod +x provisioning/lib/setup-gitea-repos.sh
	@./provisioning/lib/setup-gitea-repos.sh

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

enable-nfs: ## Enable NFS storage (manual step)
	@echo "$(YELLOW)To enable NFS, set 'nfs_enabled: true' in 'ansible/inventory/group_vars/all.yml' and re-run 'make infra'$(RESET)"

disable-nfs: ## Disable NFS storage (manual step)
	@echo "$(YELLOW)To disable NFS, set 'nfs_enabled: false' in 'ansible/inventory/group_vars/all.yml' and re-run 'make infra'$(RESET)"

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

##@ Secrets Management

install-sealed-secrets: ## Install Sealed Secrets controller
	@echo "$(CYAN)Installing Sealed Secrets controller...$(RESET)"
	kubectl apply -f kubernetes/system/sealed-secrets/controller.yaml
	@echo "$(CYAN)Waiting for Sealed Secrets controller to be ready...$(RESET)"
	kubectl wait --for=condition=available deployment/sealed-secrets-controller -n kube-system --timeout=300s
	@echo "$(GREEN)✅ Sealed Secrets controller installed$(RESET)"

##@ Git Server (Gitea)

gitea-admin-password: ## Get Gitea admin password
	@echo "$(CYAN)Gitea admin credentials:$(RESET)"
	@echo "Username: ztc-admin"
	@echo -n "Password: "
	@kubectl get secret -n gitea gitea-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "$(RED)❌ Gitea not deployed or secret not found$(RESET)"
	@echo ""
	@echo "$(CYAN)Access: http://gitea.homelab.lan$(RESET)"

##@ Private Workloads

deploy-n8n: ## Deploy n8n workflow automation platform
	@$(call deploy_workload,n8n)

deploy-uptime-kuma: ## Deploy Uptime Kuma service monitoring
	@$(call deploy_workload,uptime-kuma)

deploy-homepage: ## Deploy Homepage service dashboard
	@$(call deploy_workload,homepage)

deploy-vaultwarden: ## Deploy Vaultwarden password manager
	@$(call deploy_workload,vaultwarden)

deploy-code-server: ## Deploy Code Server development environment
	@$(call deploy_workload,code-server)

##@ Workload Undeployment

undeploy-workload: ## Undeploy specific workload (usage: make undeploy-workload WORKLOAD=n8n)
	@if [ -z "$(WORKLOAD)" ]; then \
		echo "$(RED)❌ Usage: make undeploy-workload WORKLOAD=<name>$(RESET)"; \
		echo "$(CYAN)Available workloads:$(RESET)"; \
		kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads -o jsonpath='{range .items[*]}{.metadata.labels.ztc\.homelab/template}{"\n"}{end}' 2>/dev/null | sort -u | sed 's/^/  /' || echo "  (none)"; \
		exit 1; \
	fi
	@chmod +x provisioning/lib/undeploy-workload.sh
	@./provisioning/lib/undeploy-workload.sh $(WORKLOAD)

undeploy-n8n: ## Undeploy n8n workflow automation platform
	@$(MAKE) undeploy-workload WORKLOAD=n8n

undeploy-uptime-kuma: ## Undeploy Uptime Kuma service monitoring
	@$(MAKE) undeploy-workload WORKLOAD=uptime-kuma

undeploy-homepage: ## Undeploy Homepage service dashboard
	@$(MAKE) undeploy-workload WORKLOAD=homepage

undeploy-vaultwarden: ## Undeploy Vaultwarden password manager
	@$(MAKE) undeploy-workload WORKLOAD=vaultwarden

undeploy-code-server: ## Undeploy Code Server development environment
	@$(MAKE) undeploy-workload WORKLOAD=code-server

# Helper function to deploy workloads with override support
define deploy_workload
	$(if $(STORAGE_SIZE),export OVERRIDE_STORAGE_SIZE="$(STORAGE_SIZE)";) \
	$(if $(STORAGE_CLASS),export OVERRIDE_STORAGE_CLASS="$(STORAGE_CLASS)";) \
	$(if $(HOSTNAME),export OVERRIDE_HOSTNAME="$(HOSTNAME)";) \
	$(if $(IMAGE_TAG),export OVERRIDE_IMAGE_TAG="$(IMAGE_TAG)";) \
	$(if $(MEMORY_REQUEST),export OVERRIDE_MEMORY_REQUEST="$(MEMORY_REQUEST)";) \
	$(if $(MEMORY_LIMIT),export OVERRIDE_MEMORY_LIMIT="$(MEMORY_LIMIT)";) \
	$(if $(CPU_REQUEST),export OVERRIDE_CPU_REQUEST="$(CPU_REQUEST)";) \
	$(if $(CPU_LIMIT),export OVERRIDE_CPU_LIMIT="$(CPU_LIMIT)";) \
	$(if $(ADMIN_TOKEN),export OVERRIDE_ADMIN_TOKEN="$(ADMIN_TOKEN)";) \
	$(if $(PASSWORD),export OVERRIDE_PASSWORD="$(PASSWORD)";) \
	./provisioning/lib/deploy-workload.sh $(1)
endef

list-workloads: ## List all deployed workloads
	@kubectl get applications -n argocd -l app.kubernetes.io/part-of=ztc-workloads

workload-status: ## Check specific workload status (usage: make workload-status WORKLOAD=n8n)
	@if [ -z "$(WORKLOAD)" ]; then \
		echo "$(RED)❌ Usage: make workload-status WORKLOAD=<name>$(RESET)"; \
		exit 1; \
	fi
	@kubectl get pods,svc,ingress -n $(WORKLOAD) 2>/dev/null || echo "$(YELLOW)⚠️  Workload $(WORKLOAD) not found$(RESET)"

##@ GitOps (ArgoCD)

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

lint: ## Lint Ansible, YAML, and Helm charts
	@echo "$(CYAN)Linting Ansible playbooks...$(RESET)"
	@command -v ansible-lint >/dev/null && ansible-lint ansible/ || echo "$(YELLOW)⚠️  ansible-lint not installed, skipping...$(RESET)"
	@echo "$(CYAN)Linting YAML files...$(RESET)"
	@command -v yamllint >/dev/null && yamllint . || echo "$(YELLOW)⚠️  yamllint not installed, skipping...$(RESET)"
	@echo "$(CYAN)Linting Helm charts...$(RESET)"
	@command -v helm >/dev/null && helm lint kubernetes/system/monitoring && helm lint kubernetes/system/storage || echo "$(YELLOW)⚠️  helm not installed, skipping...$(RESET)"

validate: ## Validate Kubernetes manifests against the cluster's API
	@echo "$(CYAN)Validating Kubernetes manifests...$(RESET)"
	@command -v kubeval >/dev/null && find kubernetes -name '*.yaml' -exec kubeval {} + || echo "$(YELLOW)⚠️  kubeval not installed, skipping...$(RESET)"
	@echo "$(CYAN)Dry-running Kubernetes manifests against cluster...$(RESET)"
	@find kubernetes/ -name "*.yaml" -o -name "*.yml" | xargs kubectl apply --dry-run=client -f

teardown: ## ⚠️  DESTRUCTIVE: Complete cluster teardown for development iteration
	@echo "$(RED)⚠️  WARNING: This will completely destroy the cluster and all data!$(RESET)"
	@echo "$(YELLOW)This operation will:$(RESET)"
	@echo "  • Uninstall k3s from all nodes"
	@echo "  • Clean all persistent storage (NFS)"
	@echo "  • Remove local secrets and configuration files"
	@echo "  • Clean SSH host keys"
	@echo "  • Remove generated ISOs and backups"
	@echo ""
	@echo "$(RED)This is IRREVERSIBLE and intended for development workflow.$(RESET)"
	@echo ""
	@read -p "Type 'TEARDOWN' to confirm complete cluster destruction: " confirm; \
	if [ "$${confirm}" != "TEARDOWN" ]; then \
		echo "$(YELLOW)❌ Teardown cancelled.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(CYAN)🚨 Starting complete cluster teardown...$(RESET)"
	@echo "$(CYAN)Step 1/6: Uninstalling k3s from cluster nodes...$(RESET)"
	@for node in k3s-master k3s-worker-01 k3s-worker-02 k3s-worker-03; do \
		echo "$(CYAN)  Checking $${node}...$(RESET)"; \
		if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$$(ansible-inventory -i ansible/inventory/hosts.ini --host $${node} 2>/dev/null | grep ansible_host | cut -d'"' -f4) 'test -f /usr/local/bin/k3s-uninstall.sh || test -f /usr/local/bin/k3s-agent-uninstall.sh' 2>/dev/null; then \
			echo "$(CYAN)    Uninstalling k3s from $${node}...$(RESET)"; \
			ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$$(ansible-inventory -i ansible/inventory/hosts.ini --host $${node} 2>/dev/null | grep ansible_host | cut -d'"' -f4) 'sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null || sudo /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true' || echo "$(YELLOW)    Warning: Could not uninstall k3s from $${node}$(RESET)"; \
		else \
			echo "$(YELLOW)    No k3s installation found on $${node}$(RESET)"; \
		fi; \
	done
	@echo "$(CYAN)Step 2/6: Cleaning NFS storage...$(RESET)"
	@if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$$(ansible-inventory -i ansible/inventory/hosts.ini --host k8s-storage 2>/dev/null | grep ansible_host | cut -d'"' -f4) 'test -d /export/k8s' 2>/dev/null; then \
		echo "$(CYAN)  Cleaning NFS storage directory...$(RESET)"; \
		ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$$(ansible-inventory -i ansible/inventory/hosts.ini --host k8s-storage 2>/dev/null | grep ansible_host | cut -d'"' -f4) 'sudo systemctl stop nfs-kernel-server 2>/dev/null; sudo rm -rf /export/k8s/* 2>/dev/null; sudo systemctl start nfs-kernel-server 2>/dev/null' || echo "$(YELLOW)  Warning: Could not clean NFS storage$(RESET)"; \
	else \
		echo "$(YELLOW)  No NFS storage found$(RESET)"; \
	fi
	@echo "$(CYAN)Step 3/6: Removing local secrets and configuration...$(RESET)"
	@rm -f ansible/inventory/secrets.yml || true
	@rm -f .ansible-vault-password || true
	@rm -f ansible/.vault_pass || true
	@rm -f ztc-secrets-backup-*.tar.gz.gpg || true
	@echo "$(CYAN)Step 4/6: Cleaning generated files...$(RESET)"
	@rm -f provisioning/downloads/*.iso || true
	@echo "$(CYAN)Step 5/6: Cleaning SSH host keys...$(RESET)"
	@for node in k3s-master k3s-worker-01 k3s-worker-02 k3s-worker-03 k8s-storage; do \
		node_ip=$$(ansible-inventory -i ansible/inventory/hosts.ini --host $${node} 2>/dev/null | grep ansible_host | cut -d'"' -f4); \
		if [ -n "$${node_ip}" ]; then \
			ssh-keygen -R $${node_ip} 2>/dev/null || true; \
		fi; \
	done
	@echo "$(CYAN)Step 6/6: Final verification...$(RESET)"
	@echo "$(GREEN)✅ Complete cluster teardown finished!$(RESET)"
	@echo ""
	@echo "$(CYAN)🚀 Ready for fresh setup:$(RESET)"
	@echo "  1. Run: make setup"
	@echo "  2. Create USB drives for nodes"
	@echo "  3. Boot nodes and run: make infra"
	@echo ""
	@echo "$(YELLOW)📋 Teardown Summary:$(RESET)"
	@echo "  • k3s uninstalled from all nodes"
	@echo "  • NFS storage cleaned"
	@echo "  • Local secrets removed"
	@echo "  • Generated files cleaned"
	@echo "  • SSH host keys reset"

##@ Information

logs: ## Show cluster logs (kubectl logs)
	@echo "$(CYAN)Available log commands:$(RESET)"
	@echo "kubectl logs -n kube-system <pod-name>"
	@echo "kubectl get pods --all-namespaces"

##@ Help

help: ## Display this help
	@echo "Zero Touch Cluster - Kubernetes Infrastructure Automation"
	@echo ""
	@echo "Streamlined Setup (Recommended):"
	@echo "  make setup      # Create infrastructure secrets (pre-cluster)"
	@echo "  make infra      # Deploy complete infrastructure (storage + cluster + apps)"
	@echo ""
	@echo "Quick Start (Autoinstall):"
	@echo "  make setup                                                          # Create secrets"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10  # Create USB"
	@echo "  make infra                                                          # Deploy after nodes boot"
	@echo ""
	@echo "Setup & Prerequisites:"
	@echo "  setup           Create secrets templates and check prerequisites"
	@echo "  check           Check prerequisites and system readiness"
	@echo ""
	@echo "Infrastructure:"
	@echo "  storage               Setup K8s storage server"
	@echo "  cluster               Setup k3s cluster"
	@echo "  deploy-dns            Deploy DNS server for homelab services"
	@echo "  dns-status            Check DNS server status and health"
	@echo "  copy-kubeconfig       Copy kubeconfig from master to local kubectl"
	@echo "  post-cluster-setup    Create application sealed secrets"
	@echo "  infra                 Setup complete infrastructure with GitOps (recommended)"
	@echo ""
	@echo "System Components (Helm):"
	@echo "  system-components       Deploy all system components"
	@echo "  monitoring-stack        Deploy monitoring (Prometheus, Grafana)"
	@echo "  storage-stack           Deploy hybrid storage (local-path + NFS)"
	@echo "  gitea-stack             Deploy Gitea Git server for private workloads"
	@echo "  setup-gitea-repos       Setup required repositories after Gitea deployment"
	@echo ""
	@echo "Private Workloads:"
	@echo "  deploy-n8n              Deploy n8n workflow automation platform"
	@echo "  deploy-uptime-kuma      Deploy Uptime Kuma service monitoring"
	@echo "  deploy-homepage         Deploy Homepage service dashboard"
	@echo "  deploy-vaultwarden      Deploy Vaultwarden password manager"
	@echo "  deploy-code-server      Deploy Code Server development environment"
	@echo "  list-workloads          List all deployed workloads"
	@echo "  workload-status         Check specific workload status"
	@echo ""
	@echo "Workload Undeployment:"
	@echo "  undeploy-workload       Undeploy specific workload (usage: WORKLOAD=name)"
	@echo "  undeploy-n8n            Undeploy n8n workflow automation platform"
	@echo "  undeploy-uptime-kuma    Undeploy Uptime Kuma service monitoring"
	@echo "  undeploy-homepage       Undeploy Homepage service dashboard"
	@echo "  undeploy-vaultwarden    Undeploy Vaultwarden password manager"
	@echo "  undeploy-code-server    Undeploy Code Server development environment"
	@echo ""
	@echo "Workload Customization:"
	@echo "  make deploy-n8n STORAGE_SIZE=10Gi HOSTNAME=n8n.homelab.lan"
	@echo "  make deploy-vaultwarden MEMORY_LIMIT=256Mi IMAGE_TAG=1.31.0"
	@echo "  Available overrides: STORAGE_SIZE, STORAGE_CLASS, HOSTNAME, IMAGE_TAG,"
	@echo "                      MEMORY_REQUEST, MEMORY_LIMIT, CPU_REQUEST, CPU_LIMIT"
	@echo ""
	@echo "Git Server (Gitea):"
	@echo "  gitea-admin-password    Get Gitea admin credentials"
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
	@echo "  teardown        ⚠️  DESTRUCTIVE: Complete cluster teardown for development"
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