#!/usr/bin/env bash
# Deploys the chart into a throwaway kind cluster and checks the service answers.
# CI runs this against the exact image it is about to publish; `make e2e` runs it
# locally against a fresh build.
#
#   IMAGE=ghcr.io/owner/repo:tag [IMAGE_ARCHIVE=image.tar] hack/e2e.sh
set -euo pipefail

: "${IMAGE:?set IMAGE=<repository>:<tag>}"
CLUSTER=${CLUSTER:-e2e}
NS=e2e
cd "$(dirname "$0")/.."

# Same Rollouts version the platform runs, read from the one place it is pinned.
ROLLOUTS_VERSION=$(awk '/chart: argo-rollouts/ { getline; print $2 }' deploy/argocd/apps/platform.yaml)

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config hack/kind-config-single.yaml --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

if [[ -n "${IMAGE_ARCHIVE:-}" ]]; then
  kind load image-archive "$IMAGE_ARCHIVE" --name "$CLUSTER"
else
  kind load docker-image "$IMAGE" --name "$CLUSTER"
fi

helm upgrade --install argo-rollouts argo-rollouts \
  --repo https://argoproj.github.io/argo-helm --version "$ROLLOUTS_VERSION" \
  --namespace argo-rollouts --create-namespace --wait

# Same Pod Security level as the real environments, so a securityContext
# regression fails here and not after a merge.
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NS" --overwrite pod-security.kubernetes.io/enforce=restricted

# No Prometheus in this cluster, so no PodMonitor/PrometheusRule/analysis.
# The tag-only image reference is allowed here because Kyverno isn't installed;
# real environments require the digest.
helm upgrade --install demo-service deploy/chart --namespace "$NS" \
  -f deploy/envs/staging/values.yaml \
  --set image.repository="${IMAGE%:*}" \
  --set image.tag="${IMAGE##*:}" \
  --set image.digest= \
  --set monitoring.enabled=false \
  --set analysis.enabled=false

if ! kubectl -n "$NS" wait rollout/demo-service --for=jsonpath='{.status.phase}'=Healthy --timeout=240s; then
  kubectl -n "$NS" get rollout,rs,pods -o wide
  kubectl -n "$NS" describe pods | tail -50
  kubectl -n "$NS" logs -l app.kubernetes.io/name=demo-service --tail=50 || true
  exit 1
fi

kubectl -n "$NS" port-forward svc/demo-service 18080:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -fsS localhost:18080/readyz >/dev/null 2>&1 && break; sleep 1; done

body=$(curl -fsS "localhost:18080/api/v1/greetings?name=e2e")
echo "GET /api/v1/greetings -> $body"
[[ "$body" == '{"message":"Hello, e2e!"}' ]]

status=$(curl -s -w '\n%{http_code}' "localhost:18080/api/v1/greetings?name=$(printf 'x%.0s' {1..60})" | tail -n1)
echo "GET /api/v1/greetings?name=<60 chars> -> $status"
[[ "$status" == 400 ]]

echo "e2e passed"
