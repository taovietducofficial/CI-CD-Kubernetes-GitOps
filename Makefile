SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
# Git Bash on Windows rewrites /paths passed to docker; turn that off.
export MSYS_NO_PATHCONV := 1

CLUSTER     ?= gitops
KIND_CONFIG ?= hack/kind-config.yaml
ENV         ?= staging
OUT         := .out

# Pinned in exactly one place (the Argo CD Application); read it from there.
ARGOCD_CHART_VERSION := $(shell awk '/chart: argo-cd/ { getline; print $$2 }' deploy/argocd/apps/platform.yaml)
# Environments that currently have a release (see deploy/argocd/apps/demo-service.yaml).
ENVS := $(notdir $(patsubst %/,%,$(dir $(wildcard deploy/envs/*/image.yaml))))

KUBECONFORM := docker run --rm --mount type=bind,src="$(CURDIR)",dst=/work -w /work \
  ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary -kubernetes-version 1.37.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

##@ Develop

.PHONY: test
test: ## Unit + web tests with the coverage gate
	cd app && ./mvnw -B verify

.PHONY: image
image: ## Build the container image as demo-service:dev
	docker build -t demo-service:dev app

.PHONY: lint
lint: ## Chart lint, schema, kubeconform, policy unit tests, policies vs rendered chart
	@mkdir -p $(OUT)
	helm lint deploy/chart -f deploy/chart/ci/test-values.yaml
	helm template demo-service deploy/chart -n app-staging -f deploy/chart/ci/test-values.yaml > $(OUT)/chart-ci.yaml
	@for env in $(ENVS); do \
	  echo "render $$env"; \
	  helm template demo-service deploy/chart -n app-$$env \
	    -f deploy/envs/$$env/values.yaml -f deploy/envs/$$env/image.yaml > $(OUT)/env-$$env.yaml; \
	done
	$(KUBECONFORM) $(OUT)/*.yaml
	kyverno test deploy/policies/tests
	kyverno apply deploy/policies/workload-baseline.yaml --values-file deploy/policies/tests/values.yaml \
	  $$(printf -- '--resource %s ' $(OUT)/*.yaml)

.PHONY: e2e
e2e: image ## Deploy a fresh build to a throwaway kind cluster and smoke test it
	docker tag demo-service:dev ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops:dev
	IMAGE=ghcr.io/taovietducofficial/ci-cd-kubernetes-gitops:dev hack/e2e.sh
	kind delete cluster --name e2e

##@ Local platform

.PHONY: up
up: ## Create the kind cluster and hand it over to Argo CD
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config $(KIND_CONFIG) --wait 120s
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm \
	  --version $(ARGOCD_CHART_VERSION) --namespace argocd --create-namespace \
	  -f deploy/argocd/bootstrap/values.yaml --wait
	kubectl apply -f deploy/argocd/apps/projects.yaml -f deploy/argocd/bootstrap/root.yaml
	@echo
	@echo "Argo CD is syncing the platform; first sync takes 5-10 minutes."
	@echo "  make status     watch progress"
	@echo "  make ui         open the dashboards"
	@echo "  make password   Argo CD admin password"

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

.PHONY: status
status: ## Applications and rollouts at a glance
	kubectl -n argocd get applications -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
	@echo
	kubectl get rollouts -A 2>/dev/null || true

.PHONY: password
password: ## Print the initial Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: ui
ui: ## Port-forward Argo CD :8080, Grafana :3000, Prometheus :9090, Rollouts :3100
	@echo "Argo CD    http://localhost:8080  (admin / make password)"
	@echo "Grafana    http://localhost:3000  (admin / prom-operator)"
	@echo "Prometheus http://localhost:9090"
	@echo "Rollouts   http://localhost:3100/rollouts"
	@trap 'kill 0' EXIT; \
	kubectl -n argocd port-forward svc/argocd-server 8080:80 >/dev/null & \
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 >/dev/null & \
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null & \
	kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100 >/dev/null & \
	wait

##@ Operate

.PHONY: seal
seal: ## Encrypt a secret value for ENV: printf 'value' | make seal ENV=staging
	@kubeseal --raw --namespace app-$(ENV) --name demo-service --from-file=/dev/stdin; echo

.PHONY: load
load: ## Send steady traffic to ENV (needed for canary analysis to have data)
	kubectl run load-$(ENV) --image=curlimages/curl:8.17.0 --restart=Never --command -- \
	  sh -c 'while true; do curl -s -o /dev/null http://demo-service.app-$(ENV)/api/v1/greetings; sleep 0.05; done'

.PHONY: load-stop
load-stop: ## Stop the traffic generator for ENV
	kubectl delete pod load-$(ENV) --ignore-not-found

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"} /^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
