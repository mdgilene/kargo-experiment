# Bootstrap the whole Kargo + Argo CD + Argo Rollouts + Helm test environment on a local kind cluster.
#
#   make bootstrap                      # cluster + cert-manager + Argo CD + Rollouts + Kargo + this repo
#   GITHUB_USER=me GITHUB_TOKEN=xxx make bootstrap   # also give Kargo/Argo CD git credentials
#   make help
#
# Requires: docker, kind, kubectl, helm.

SHELL := /bin/bash
.DEFAULT_GOAL := help

CLUSTER_NAME ?= kargo-quickstart
KUBE_CONTEXT := kind-$(CLUSTER_NAME)

CERT_MANAGER_VERSION  ?= 1.19.3
ARGOCD_CHART_VERSION  ?= 9.4.3
ROLLOUTS_CHART_VERSION ?= 2.40.6
KARGO_CHART_VERSION   ?= 1.12.5

# Git repository Kargo/Argo CD promote from (must match the repoURL in kargo/ and apps/).
REPO_URL     ?= https://github.com/mdgilene/kargo-experiment.git
KARGO_PROJECT ?= kargo-hello-world
# Optional: needed for Kargo to push stage branches (token with repo scope).
GITHUB_USER  ?=
GITHUB_TOKEN ?=

# Local-only demo credentials (same as the Kargo quickstart): Argo CD admin/admin, Kargo admin/admin.
ARGOCD_PASSWORD_HASH := $$2a$$10$$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO
KARGO_PASSWORD_HASH  := $$pbkdf2-sha256$$600000$$Fc8fnFyUR9wjfx7Mu0BuEA$$IIOU/KwMqEZuFpq0uAGwJTLTgrI0Ep8g7p.XRgId3Ks
KARGO_SIGNING_KEY    := iwishtowashmyirishwristwatch

KUBECTL := kubectl --context $(KUBE_CONTEXT)
HELM    := helm --kube-context $(KUBE_CONTEXT)

.PHONY: help bootstrap check-tools cluster cert-manager argocd argo-rollouts kargo project credentials apps \
        urls status teardown

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: check-tools cluster cert-manager argocd argo-rollouts kargo project credentials apps urls ## Build everything from scratch

check-tools: ## Verify required CLIs are installed
	@for t in docker kind kubectl helm; do \
	  command -v $$t >/dev/null || { echo "missing required tool: $$t"; exit 1; }; \
	done

cluster: ## Create the kind cluster (no-op if it exists)
	@if kind get clusters | grep -qx '$(CLUSTER_NAME)'; then \
	  echo "kind cluster '$(CLUSTER_NAME)' already exists"; \
	else \
	  kind create cluster --wait 120s --config hack/kind-cluster.yaml; \
	fi
	@$(KUBECTL) cluster-info >/dev/null

cert-manager: ## Install cert-manager (required by Kargo)
	$(HELM) upgrade --install cert-manager cert-manager \
	  --repo https://charts.jetstack.io --version $(CERT_MANAGER_VERSION) \
	  --namespace cert-manager --create-namespace \
	  --set crds.enabled=true --wait

argocd: ## Install Argo CD (UI on http://localhost:31080, admin/admin)
	$(HELM) upgrade --install argocd argo-cd \
	  --repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART_VERSION) \
	  --namespace argocd --create-namespace \
	  --set 'configs.secret.argocdServerAdminPassword=$(ARGOCD_PASSWORD_HASH)' \
	  --set dex.enabled=false \
	  --set notifications.enabled=false \
	  --set server.service.type=NodePort \
	  --set server.service.nodePortHttp=31080 \
	  --set 'server.extraArgs={--insecure}' \
	  --set server.extensions.enabled=true \
	  --set 'server.extensions.extensionList[0].name=argo-rollouts' \
	  --set 'server.extensions.extensionList[0].env[0].name=EXTENSION_URL' \
	  --set 'server.extensions.extensionList[0].env[0].value=https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.7/extension.tar' \
	  --wait

argo-rollouts: ## Install Argo Rollouts
	$(HELM) upgrade --install argo-rollouts argo-rollouts \
	  --repo https://argoproj.github.io/argo-helm --version $(ROLLOUTS_CHART_VERSION) \
	  --namespace argo-rollouts --create-namespace --wait

kargo: ## Install Kargo (UI on http://localhost:31081, admin/admin)
	$(HELM) upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
	  --version $(KARGO_CHART_VERSION) \
	  --namespace kargo --create-namespace \
	  --set api.service.type=NodePort \
	  --set api.service.nodePort=31081 \
	  --set 'server.extraArgs={--insecure}' \
	  --set api.tls.enabled=false \
	  --set 'api.adminAccount.passwordHash=$(KARGO_PASSWORD_HASH)' \
	  --set api.adminAccount.tokenSigningKey=$(KARGO_SIGNING_KEY) \
	  --set externalWebhooksServer.service.type=NodePort \
	  --set externalWebhooksServer.service.nodePort=31082 \
	  --set externalWebhooksServer.tls.enabled=false \
	  --wait

project: ## Apply the Kargo Project, Warehouse, Stages and analysis templates
	$(KUBECTL) apply -f kargo/project.yaml
	$(KUBECTL) wait --for=jsonpath='{.status.phase}'=Active namespace/$(KARGO_PROJECT) --timeout=60s 2>/dev/null || true
	$(KUBECTL) apply -f kargo/

credentials: ## Create git credentials for Kargo and Argo CD (only if GITHUB_USER and GITHUB_TOKEN are set)
	@if [ -n "$(GITHUB_USER)" ] && [ -n "$(GITHUB_TOKEN)" ]; then \
	  echo "creating git credentials"; \
	  $(KUBECTL) -n $(KARGO_PROJECT) create secret generic github-creds \
	    --from-literal=repoURL=$(REPO_URL) --from-literal=username=$(GITHUB_USER) \
	    --from-literal=password=$(GITHUB_TOKEN) --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	  $(KUBECTL) -n $(KARGO_PROJECT) label secret github-creds kargo.akuity.io/cred-type=git --overwrite; \
	  $(KUBECTL) -n argocd create secret generic repo-creds \
	    --from-literal=type=git --from-literal=url=$(REPO_URL) --from-literal=username=$(GITHUB_USER) \
	    --from-literal=password=$(GITHUB_TOKEN) --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	  $(KUBECTL) -n argocd label secret repo-creds argocd.argoproj.io/secret-type=repository --overwrite; \
	else \
	  echo "GITHUB_USER/GITHUB_TOKEN not set: skipping git credentials."; \
	  echo "Kargo cannot push stage branches without them (see README)."; \
	fi

apps: ## Install the app-of-apps root Applications (dev, staging, prod)
	$(KUBECTL) apply -f argocd/

urls: ## Print UI/app URLs
	@echo ""
	@echo "Argo CD:  http://localhost:31080   (admin / admin)"
	@echo "Kargo:    http://localhost:31081   (admin / admin)"
	@echo "hello-world: dev http://localhost:32080  staging http://localhost:32081  prod http://localhost:32082"
	@echo "hello-api:   ClusterIP only: kubectl -n hello-api-dev port-forward svc/hello-api-dev 8081:8080"

status: ## Show Argo CD apps and Kargo stages/freight
	@$(KUBECTL) get applications -n argocd
	@$(KUBECTL) get warehouse,stage,freight -n $(KARGO_PROJECT)

teardown: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)
