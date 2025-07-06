# Zero Touch Cluster Makefile

.PHONY: help prepare check setup storage cluster deploy-dns dns-status copy-kubeconfig post-cluster-setup system-components monitoring-stack storage-stack longhorn-stack setup-gitea-repos homepage-stack deploy-storage deploy-nfs enable-nfs disable-nfs enable-longhorn disable-longhorn longhorn-status credentials show-credentials show-passwords argocd argocd-apps gitops-status gitops-sync status autoinstall-usb cidata-iso cidata-usb usb-list ping restart-node drain-node uncordon-node lint validate teardown logs undeploy-workload undeploy-n8n undeploy-uptime-kuma undeploy-code-server deploy-bundle-starter deploy-bundle-monitoring deploy-bundle-productivity deploy-bundle-security deploy-bundle-development list-bundles bundle-status deploy-custom-app deploy-gitea-runner registry-login registry-info

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

check: ## Check prerequisites and system readiness
	@echo "$(CYAN)Checking prerequisites...$(RESET)"
	@command -v ansible >/dev/null || (echo "$(RED)❌ Ansible not installed$(RESET)" && exit 1)
	@command -v ansible-vault >/dev/null || (echo "$(RED)❌ Ansible Vault not available$(RESET)" && exit 1)
	@command -v kubectl >/dev/null || echo "$(YELLOW)⚠️  kubectl not available (will be configured after cluster deployment)$(RESET)"
	@command -v helm >/dev/null || (echo "$(RED)❌ Helm not installed$(RESET)" && exit 1)
	@echo "$(GREEN)✅ Prerequisites check complete$(RESET)"

prepare: ## Interactive wizard to prepare infrastructure secrets and prerequisites
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
		echo "$(RED)❌ Ansible Vault password file not found. Run 'make prepare' first.$(RESET)"; \
		exit 1; \
	fi
	@command -v kubectl >/dev/null || (echo "$(RED)❌ kubectl not installed$(RESET)" && exit 1)
	@command -v gpg >/dev/null || (echo "$(RED)❌ GPG not installed$(RESET)" && exit 1)
	@kubectl cluster-info >/dev/null 2>&1 || (echo "$(RED)❌ Cluster not accessible. Cannot backup sealed secrets$(RESET)" && exit 1)
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
		echo "$(CYAN)Testing cluster connectivity...$(RESET)"; \
		if kubectl cluster-info >/dev/null 2>&1; then \
			echo "$(GREEN)✅ Cluster is accessible$(RESET)"; \
		else \
			echo "$(YELLOW)⚠️  Cluster may still be starting up$(RESET)"; \
		fi; \
	else \
		echo "$(RED)❌ Kubeconfig not found at ~/.kube/k3s-master-config$(RESET)"; \
		echo "$(YELLOW)This usually means:$(RESET)"; \
		echo "  1. The k3s cluster hasn't been deployed yet (run 'make cluster')"; \
		echo "  2. The cluster deployment failed"; \
		echo "  3. You're running this before cluster setup"; \
		echo "$(CYAN)💡 Correct sequence: make deploy-storage-server → make cluster → make copy-kubeconfig$(RESET)"; \
		exit 1; \
	fi

post-cluster-setup: ## Create sealed secrets for applications
	@echo "$(CYAN)Creating application sealed secrets...$(RESET)"
	@chmod +x provisioning/lib/post-cluster-setup.sh
	@./provisioning/lib/post-cluster-setup.sh

##@ Infrastructure Deployment

deploy-storage-server: check ## Setup physical storage server for Kubernetes
	@echo "$(CYAN)Deploying physical storage server...$(RESET)"
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

setup: check deploy-storage-server cluster copy-kubeconfig install-sealed-secrets storage post-cluster-setup deploy-dns system-components setup-gitea-repos argocd ## Deploy complete Zero Touch Cluster infrastructure with GitOps
	@echo "$(GREEN)✅ Complete Zero Touch Cluster infrastructure deployed!$(RESET)"
	@echo "$(CYAN)🔐 Access credentials via Vaultwarden: make credentials$(RESET)"
	@echo "$(CYAN)Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:80$(RESET)"
	@echo "$(CYAN)ArgoCD URL: http://argocd.homelab.lan (after DNS setup)$(RESET)"
	@echo "$(YELLOW)📋 Next Steps:$(RESET)"
	@echo "  1. Configure your router to use 192.168.50.20 as DNS server"
	@echo "  2. Test: curl http://argocd.homelab.lan"
	@echo "  3. Documentation: see docs/dns-setup.md"

##@ System Components (Helm Charts)

system-components: monitoring-stack gitea-stack homepage-stack ## Deploy all system components
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

storage: ## Deploy storage components (Usage: make storage [NFS=false] [LONGHORN=true])
	@echo "$(CYAN)Deploying storage stack...$(RESET)"
	@command -v helm >/dev/null || (echo "$(RED)❌ Helm not installed$(RESET)" && exit 1)
	@kubectl cluster-info >/dev/null 2>&1 || (echo "$(RED)❌ Cluster not accessible. Run 'make copy-kubeconfig' first$(RESET)" && exit 1)
	@echo "$(CYAN)Options: NFS=$(if $(NFS),$(NFS),enabled), LONGHORN=$(if $(LONGHORN),$(LONGHORN),disabled)$(RESET)"
	@if [ "$(LONGHORN)" = "true" ]; then \
		echo "$(YELLOW)⚠️  Longhorn requires open-iscsi on all nodes$(RESET)"; \
		echo "$(YELLOW)⚠️  Ensure nodes have been provisioned with Longhorn support$(RESET)"; \
	fi
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		$(if $(filter false,$(NFS)),--set nfs.enabled=false) \
		$(if $(filter true,$(LONGHORN)),--set longhorn.enabled=true) \
		--wait --timeout 5m
	@echo "$(GREEN)✅ Storage stack deployed$(RESET)"


gitea-stack: ## Deploy Gitea Git server for private workloads
	@echo "$(CYAN)Deploying Gitea Git server...$(RESET)"
	@if [ ! -f kubernetes/system/gitea/values-secret.yaml ]; then \
		echo "$(YELLOW)⚠️  Creating values-secret.yaml from template...$(RESET)"; \
		cp kubernetes/system/gitea/values-secret.yaml.template kubernetes/system/gitea/values-secret.yaml; \
		echo "$(RED)❗ Run 'make prepare' to generate proper SealedSecret for Gitea admin$(RESET)"; \
	fi
	@echo "$(CYAN)Updating Helm dependencies...$(RESET)"
	helm dependency update kubernetes/system/gitea/
	@echo "$(CYAN)Installing Gitea (this may take 2-3 minutes)...$(RESET)"
	helm upgrade --install gitea ./kubernetes/system/gitea \
		--namespace gitea \
		--create-namespace \
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

homepage-stack: ## Deploy Homepage entry point dashboard
	@echo "$(CYAN)Deploying ZTC Homepage dashboard...$(RESET)"
	@echo "$(CYAN)Installing Homepage entry point (root domain)...$(RESET)"
	helm upgrade --install homepage ./kubernetes/system/homepage \
		--namespace homepage \
		--create-namespace \
		--values ./kubernetes/system/homepage/values.yaml \
		--wait --timeout 10m
	@echo "$(GREEN)✅ ZTC Homepage deployed$(RESET)"
	@echo "$(CYAN)🏠 Primary entry point: http://homelab.lan$(RESET)"
	@echo "$(YELLOW)ℹ️  Homepage provides unified access to all ZTC services$(RESET)"

##@ Storage Management

storage-status: ## Check storage deployment status and available storage classes
	@echo "$(CYAN)Storage Classes:$(RESET)"
	@kubectl get storageclass 2>/dev/null || echo "$(YELLOW)⚠️  kubectl not configured or cluster not accessible$(RESET)"
	@echo ""
	@echo "$(CYAN)Storage Pods:$(RESET)"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=nfs-subdir-external-provisioner 2>/dev/null || echo "$(YELLOW)⚠️  NFS provisioner not deployed$(RESET)"
	@kubectl get pods -n longhorn-system 2>/dev/null || echo "$(YELLOW)⚠️  Longhorn not deployed$(RESET)"

longhorn-stack: ## Deploy Longhorn distributed storage (for 3+ node clusters)
	@echo "$(CYAN)Deploying Longhorn distributed storage...$(RESET)"
	@echo "$(YELLOW)Prerequisites: open-iscsi installed on all nodes$(RESET)"
	helm upgrade --install storage ./kubernetes/system/storage \
		--namespace kube-system \
		--values ./kubernetes/system/storage/values.yaml \
		--set longhorn.enabled=true \
		--wait --timeout 15m
	@echo "$(GREEN)✅ Longhorn deployed$(RESET)"
	@echo "$(CYAN)Checking Longhorn status...$(RESET)"
	@sleep 30
	@kubectl get pods -n longhorn-system 2>/dev/null || echo "$(YELLOW)Longhorn pods starting...$(RESET)"
	@echo "$(CYAN)Access Longhorn UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80$(RESET)"


longhorn-status: ## Check Longhorn deployment status
	@echo "$(CYAN)Checking Longhorn status...$(RESET)"
	@if kubectl get namespace longhorn-system >/dev/null 2>&1; then \
		echo "$(GREEN)✅ Longhorn namespace exists$(RESET)"; \
		kubectl get pods -n longhorn-system; \
		echo ""; \
		kubectl get storageclass longhorn 2>/dev/null && echo "$(GREEN)✅ Longhorn storage class available$(RESET)" || echo "$(YELLOW)⚠️  Longhorn storage class not found$(RESET)"; \
		echo ""; \
		echo "$(CYAN)Longhorn UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80$(RESET)"; \
	else \
		echo "$(RED)❌ Longhorn not deployed$(RESET)"; \
		echo "$(YELLOW)Deploy with: make longhorn-stack$(RESET)"; \
	fi

##@ Credential Management

credentials: show-credentials ## Show system credentials (alias for show-credentials)

show-credentials: ## Show system credentials (Usage: make show-credentials [SERVICE=gitea|grafana|argocd])
	@if [ -n "$(SERVICE)" ]; then \
		case "$(SERVICE)" in \
			gitea) \
				echo "$(CYAN)🦊 Gitea (Git Server):$(RESET)"; \
				if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
					echo "  URL: http://gitea.homelab.lan"; \
					echo "  Username: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.username}' | base64 -d)"; \
					echo "  Password: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
				else echo "  $(RED)❌ Not deployed$(RESET)"; fi ;; \
			grafana) \
				echo "$(CYAN)📊 Grafana (Monitoring):$(RESET)"; \
				if kubectl get secret -n monitoring grafana-admin-secret >/dev/null 2>&1; then \
					echo "  URL: http://grafana.homelab.lan"; \
					echo "  Username: admin"; \
					echo "  Password: $$(kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)"; \
				else echo "  $(RED)❌ Not deployed$(RESET)"; fi ;; \
			argocd) \
				echo "$(CYAN)🚀 ArgoCD (GitOps):$(RESET)"; \
				if kubectl get secret -n argocd argocd-initial-admin-secret >/dev/null 2>&1; then \
					echo "  URL: http://argocd.homelab.lan"; \
					echo "  Username: admin"; \
					echo "  Password: $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
				else echo "  $(RED)❌ Not deployed$(RESET)"; fi ;; \
			*) echo "$(RED)❌ Unknown service: $(SERVICE)$(RESET)"; \
			   echo "$(YELLOW)Available services: gitea, grafana, argocd$(RESET)" ;; \
		esac; \
	else \
		echo "$(CYAN)ZTC System Service Credentials:$(RESET)"; \
		echo ""; \
		echo "$(GREEN)📊 Grafana (Monitoring):$(RESET)"; \
		if kubectl get secret -n monitoring grafana-admin-secret >/dev/null 2>&1; then \
			echo "  URL: http://grafana.homelab.lan"; \
			echo "  Username: admin"; \
			echo "  Password: $$(kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)"; \
		else echo "  $(RED)❌ Not deployed$(RESET)"; fi; \
		echo ""; \
		echo "$(GREEN)🦊 Gitea (Git Server):$(RESET)"; \
		if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
			echo "  URL: http://gitea.homelab.lan"; \
			echo "  Username: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.username}' | base64 -d)"; \
			echo "  Password: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
		else echo "  $(RED)❌ Not deployed$(RESET)"; fi; \
		echo ""; \
		echo "$(GREEN)🚀 ArgoCD (GitOps):$(RESET)"; \
		if kubectl get secret -n argocd argocd-initial-admin-secret >/dev/null 2>&1; then \
			echo "  URL: http://argocd.homelab.lan"; \
			echo "  Username: admin"; \
			echo "  Password: $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
		else echo "  $(RED)❌ Not deployed$(RESET)"; fi; \
		echo ""; \
		echo "$(CYAN)💡 Tip: Use 'make show-credentials SERVICE=<service>' for specific credentials$(RESET)"; \
		echo "$(CYAN)💡 Show specific service: make show-credentials SERVICE=gitea$(RESET)"; \
	fi

show-password: ## Show password for specific service (Usage: make show-password SERVICE=gitea)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)❌ Usage: make show-password SERVICE=<service>$(RESET)"; \
		echo "$(YELLOW)Available services: gitea, grafana, argocd$(RESET)"; \
		exit 1; \
	fi
	@case "$(SERVICE)" in \
		gitea) \
			if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
				kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo; \
			else echo "$(RED)❌ Gitea not deployed$(RESET)"; fi ;; \
		grafana) \
			if kubectl get secret -n monitoring grafana-admin-secret >/dev/null 2>&1; then \
				kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d; echo; \
			else echo "$(RED)❌ Grafana not deployed$(RESET)"; fi ;; \
		argocd) \
			if kubectl get secret -n argocd argocd-initial-admin-secret >/dev/null 2>&1; then \
				kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo; \
			else echo "$(RED)❌ ArgoCD not deployed$(RESET)"; fi ;; \
		*) echo "$(RED)❌ Unknown service: $(SERVICE)$(RESET)"; \
		   echo "$(YELLOW)Available services: gitea, grafana, argocd$(RESET)" ;; \
	esac

copy-password: ## Copy password to clipboard (Usage: make copy-password SERVICE=gitea)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)❌ Usage: make copy-password SERVICE=<service>$(RESET)"; \
		echo "$(YELLOW)Available services: gitea, grafana, argocd$(RESET)"; \
		exit 1; \
	fi
	@case "$(SERVICE)" in \
		gitea) \
			if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
				if command -v pbcopy >/dev/null 2>&1; then \
					kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d | pbcopy; \
					echo "$(GREEN)✅ Gitea password copied to clipboard$(RESET)"; \
				elif command -v xclip >/dev/null 2>&1; then \
					kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d | xclip -selection clipboard; \
					echo "$(GREEN)✅ Gitea password copied to clipboard$(RESET)"; \
				else \
					echo "$(YELLOW)⚠️  No clipboard tool available. Password:$(RESET)"; \
					kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo; \
				fi; \
			else echo "$(RED)❌ Gitea not deployed$(RESET)"; fi ;; \
		grafana) \
			if kubectl get secret -n monitoring grafana-admin-secret >/dev/null 2>&1; then \
				if command -v pbcopy >/dev/null 2>&1; then \
					kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d | pbcopy; \
					echo "$(GREEN)✅ Grafana password copied to clipboard$(RESET)"; \
				elif command -v xclip >/dev/null 2>&1; then \
					kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d | xclip -selection clipboard; \
					echo "$(GREEN)✅ Grafana password copied to clipboard$(RESET)"; \
				else \
					echo "$(YELLOW)⚠️  No clipboard tool available. Password:$(RESET)"; \
					kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d; echo; \
				fi; \
			else echo "$(RED)❌ Grafana not deployed$(RESET)"; fi ;; \
		argocd) \
			if kubectl get secret -n argocd argocd-initial-admin-secret >/dev/null 2>&1; then \
				if command -v pbcopy >/dev/null 2>&1; then \
					kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | pbcopy; \
					echo "$(GREEN)✅ ArgoCD password copied to clipboard$(RESET)"; \
				elif command -v xclip >/dev/null 2>&1; then \
					kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d | xclip -selection clipboard; \
					echo "$(GREEN)✅ ArgoCD password copied to clipboard$(RESET)"; \
				else \
					echo "$(YELLOW)⚠️  No clipboard tool available. Password:$(RESET)"; \
					kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo; \
				fi; \
			else echo "$(RED)❌ ArgoCD not deployed$(RESET)"; fi ;; \
		*) echo "$(RED)❌ Unknown service: $(SERVICE)$(RESET)"; \
		   echo "$(YELLOW)Available services: gitea, grafana, argocd$(RESET)" ;; \
	esac

export-credentials: ## Export all credentials to file (Usage: make export-credentials [FILE=backup.txt])
	@BACKUP_FILE="$${FILE:-ztc-credentials-$$(date +%Y%m%d-%H%M%S).txt}"; \
	echo "$(CYAN)Exporting all credentials to $$BACKUP_FILE...$(RESET)"; \
	{ \
		echo "# Zero Touch Cluster Credentials Export"; \
		echo "# Generated: $$(date)"; \
		echo ""; \
		echo "## Grafana (Monitoring)"; \
		echo "URL: http://grafana.homelab.lan"; \
		echo "Username: admin"; \
		if kubectl get secret -n monitoring grafana-admin-secret >/dev/null 2>&1; then \
			echo "Password: $$(kubectl get secret -n monitoring grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)"; \
		else echo "Password: [NOT DEPLOYED]"; fi; \
		echo ""; \
		echo "## Gitea (Git Server)"; \
		echo "URL: http://gitea.homelab.lan"; \
		if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
			echo "Username: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.username}' | base64 -d)"; \
			echo "Password: $$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
		else echo "Username: [NOT DEPLOYED]"; echo "Password: [NOT DEPLOYED]"; fi; \
		echo ""; \
		echo "## ArgoCD (GitOps)"; \
		echo "URL: http://argocd.homelab.lan"; \
		echo "Username: admin"; \
		if kubectl get secret -n argocd argocd-initial-admin-secret >/dev/null 2>&1; then \
			echo "Password: $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"; \
		else echo "Password: [NOT DEPLOYED]"; fi; \
	} > "$$BACKUP_FILE"; \
	echo "$(GREEN)✅ Credentials exported to $$BACKUP_FILE$(RESET)"; \
	echo "$(YELLOW)💡 Secure this file and store in a safe location$(RESET)"

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

##@ Private Workloads

deploy-n8n: ## Deploy n8n workflow automation platform
	@$(call deploy_workload,n8n)

deploy-uptime-kuma: ## Deploy Uptime Kuma service monitoring
	@$(call deploy_workload,uptime-kuma)

deploy-vaultwarden: ## Deploy Vaultwarden password manager
	@$(call deploy_workload,vaultwarden)

deploy-code-server: ## Deploy Code Server development environment
	@$(call deploy_workload,code-server)

deploy-gitea-runner: ## Deploy Gitea Actions CI/CD runner
	@$(call deploy_workload,gitea-runner)

##@ Custom Applications

deploy-custom-app: ## Deploy custom application from ZTC registry (Usage: make deploy-custom-app APP_NAME=myapp [IMAGE_TAG=latest])
	@if [ -z "$(APP_NAME)" ]; then \
		echo "$(RED)❌ Usage: make deploy-custom-app APP_NAME=<name> [IMAGE_TAG=<tag>]$(RESET)"; \
		echo "$(CYAN)Example: make deploy-custom-app APP_NAME=my-web-app IMAGE_TAG=v1.0.0$(RESET)"; \
		exit 1; \
	fi
	@$(call deploy_custom_app,$(APP_NAME))

##@ Container Registry

registry-login: ## Login to ZTC container registry
	@echo "$(CYAN)Logging into ZTC container registry...$(RESET)"
	@if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
		GITEA_USER=$$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.username}' | base64 -d); \
		GITEA_PASSWORD=$$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d); \
		echo "$$GITEA_PASSWORD" | docker login gitea.homelab.lan:5000 -u "$$GITEA_USER" --password-stdin; \
		echo "$(GREEN)✅ Logged into registry as $$GITEA_USER$(RESET)"; \
	else \
		echo "$(RED)❌ Gitea admin credentials not found$(RESET)"; \
		exit 1; \
	fi

registry-info: ## Show ZTC container registry information
	@echo "$(CYAN)ZTC Container Registry Information:$(RESET)"
	@echo "  Registry URL: gitea.homelab.lan:5000"
	@echo "  Web Interface: http://gitea.homelab.lan"
	@if kubectl get secret -n gitea gitea-admin-secret >/dev/null 2>&1; then \
		GITEA_USER=$$(kubectl get secret -n gitea gitea-admin-secret -o jsonpath='{.data.username}' | base64 -d); \
		echo "  Username: $$GITEA_USER"; \
		echo "  $(YELLOW)Use 'make registry-login' to authenticate Docker client$(RESET)"; \
	else \
		echo "  $(RED)❌ Gitea not deployed$(RESET)"; \
	fi

##@ Workload Bundles

deploy-bundle-starter: ## Deploy starter bundle - essential homelab services
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh starter

deploy-bundle-monitoring: ## Deploy monitoring bundle - comprehensive monitoring solution
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh monitoring

deploy-bundle-productivity: ## Deploy productivity bundle - development and automation tools
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh productivity

deploy-bundle-security: ## Deploy security bundle - password management and security tools
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh security

deploy-bundle-development: ## Deploy development bundle - complete CI/CD and development toolkit
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh development

list-bundles: ## List all available workload bundles
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh --list

bundle-status: ## Show deployment status of all bundles
	@chmod +x provisioning/lib/deploy-bundle.sh
	@./provisioning/lib/deploy-bundle.sh --status

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

# Helper function to deploy custom applications with app-specific overrides
define deploy_custom_app
	$(if $(IMAGE_TAG),export OVERRIDE_IMAGE_TAG="$(IMAGE_TAG)";) \
	$(if $(IMAGE_REGISTRY),export OVERRIDE_IMAGE_REGISTRY="$(IMAGE_REGISTRY)";) \
	$(if $(IMAGE_REPOSITORY),export OVERRIDE_IMAGE_REPOSITORY="$(IMAGE_REPOSITORY)";) \
	$(if $(GITEA_USER),export OVERRIDE_GITEA_USER="$(GITEA_USER)";) \
	$(if $(PORT),export OVERRIDE_PORT="$(PORT)";) \
	$(if $(REPLICAS),export OVERRIDE_REPLICAS="$(REPLICAS)";) \
	$(if $(STORAGE_ENABLED),export OVERRIDE_STORAGE_ENABLED="$(STORAGE_ENABLED)";) \
	$(if $(STORAGE_SIZE),export OVERRIDE_STORAGE_SIZE="$(STORAGE_SIZE)";) \
	$(if $(STORAGE_CLASS),export OVERRIDE_STORAGE_CLASS="$(STORAGE_CLASS)";) \
	$(if $(HOSTNAME),export OVERRIDE_HOSTNAME="$(HOSTNAME)";) \
	$(if $(MEMORY_REQUEST),export OVERRIDE_MEMORY_REQUEST="$(MEMORY_REQUEST)";) \
	$(if $(MEMORY_LIMIT),export OVERRIDE_MEMORY_LIMIT="$(MEMORY_LIMIT)";) \
	$(if $(CPU_REQUEST),export OVERRIDE_CPU_REQUEST="$(CPU_REQUEST)";) \
	$(if $(CPU_LIMIT),export OVERRIDE_CPU_LIMIT="$(CPU_LIMIT)";) \
	export OVERRIDE_APP_NAME="$(1)"; \
	./provisioning/lib/deploy-workload.sh custom-app
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
	@echo "  1. Run: make prepare"
	@echo "  2. Create USB drives for nodes"
	@echo "  3. Boot nodes and run: make setup"
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
	@echo "$(CYAN)Zero Touch Cluster - Kubernetes Infrastructure Automation$(RESET)"
	@echo ""
	@echo "$(GREEN)🚀 Quick Start:$(RESET)"
	@echo "  make check      # Check prerequisites"
	@echo "  make prepare    # Create infrastructure secrets"
	@echo "  make setup      # Deploy complete infrastructure"
	@echo ""
	@echo "$(GREEN)📋 Common Operations:$(RESET)"
	@echo "  make status             # Check cluster health"
	@echo "  make credentials        # Open credential manager UI"
	@echo "  make show-credentials   # Show all service credentials"
	@echo "  make storage            # Deploy/update storage"
	@echo "  make backup-secrets     # Create encrypted backup"
	@echo ""
	@echo "$(GREEN)🏗️  Infrastructure Components:$(RESET)"
	@echo "  make deploy-storage-server   # Setup physical storage server"
	@echo "  make storage                 # Deploy K8s storage (local-path + NFS)"
	@echo "  make storage NFS=false       # Deploy storage without NFS"
	@echo "  make storage LONGHORN=true   # Deploy storage with Longhorn"
	@echo "  make storage-status          # Check storage deployment"
	@echo "  make monitoring-stack        # Deploy monitoring (Prometheus, Grafana)"
	@echo "  make gitea-stack             # Deploy Git server"
	@echo ""
	@echo "$(GREEN)📱 Private Workloads:$(RESET)"
	@echo "  make deploy-n8n              # Deploy workflow automation"
	@echo "  make deploy-uptime-kuma      # Deploy service monitoring"
	@echo "  make deploy-homepage         # Deploy service dashboard"
	@echo "  make deploy-code-server      # Deploy VS Code in browser"
	@echo "  make undeploy-workload WORKLOAD=n8n  # Remove workload"
	@echo "  make list-workloads          # List deployed workloads"
	@echo ""
	@echo "$(GREEN)💿 USB Provisioning:$(RESET)"
	@echo "  make autoinstall-usb DEVICE=/dev/sdb HOSTNAME=k3s-master IP_OCTET=10"
	@echo "  make cidata-usb DEVICE=/dev/sdc HOSTNAME=k3s-worker-01 IP_OCTET=11"
	@echo "  make usb-list                # List available USB devices"
	@echo ""
	@echo "$(GREEN)🔧 GitOps (ArgoCD):$(RESET)"
	@echo "  make argocd          # Install ArgoCD"
	@echo "  make gitops-status   # Check application status"
	@echo "  make gitops-sync     # Force sync applications"
	@echo ""
	@echo "$(GREEN)🔧 Development:$(RESET)"
	@echo "  make lint            # Lint code and configurations"
	@echo "  make validate        # Validate Kubernetes manifests"
	@echo "  make teardown        # ⚠️  DESTRUCTIVE: Reset everything"
	@echo ""
	@echo "$(GREEN)🎛️  Advanced:$(RESET)"
	@echo "  make longhorn-stack          # Deploy distributed storage"
	@echo "  make deploy-dns              # Deploy DNS server"
	@echo "  make ping                    # Test node connectivity"
	@echo "  make restart-node NODE=name  # Restart specific node"
	@echo ""
	@echo "$(YELLOW)💡 Examples:$(RESET)"
	@echo "  make show-credentials SERVICE=gitea   # Show specific service"
	@echo "  make deploy-n8n STORAGE_SIZE=5Gi      # Deploy with custom storage"
	@echo "  make storage NFS=false LONGHORN=true  # Custom storage configuration"