#!/usr/bin/env bash
# Deploys the OTel demo to a 4-node kind cluster, shipping telemetry to Elastic Serverless.
# Usage: ELASTIC_OTLP_ENDPOINT=<endpoint> ELASTIC_API_KEY=<key> ./deploy/kind/install.sh
set -euo pipefail

: "${ELASTIC_OTLP_ENDPOINT:?Set ELASTIC_OTLP_ENDPOINT (e.g. https://<project>.ingest.<region>.aws.elastic.cloud:443)}"
: "${ELASTIC_API_KEY:?Set ELASTIC_API_KEY before running}"
ONBOARDING_ID="${ONBOARDING_ID:-fd8f5cc7-21fc-46a5-b84d-2519c90d83ab}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. kind cluster (1 control plane + 3 workers)
if ! kind get clusters | grep -qx otel-demo; then
  kind create cluster --name otel-demo --config "$HERE/kind-otel.yaml"
fi
kubectl get nodes

# 2. Helm repo
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
helm repo update

# 3. EDOT collector (kube-stack) -> Elastic Serverless
kubectl create namespace opentelemetry-operator-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic elastic-secret-otel \
  --namespace opentelemetry-operator-system \
  --from-literal=elastic_otlp_endpoint="$ELASTIC_OTLP_ENDPOINT" \
  --from-literal=elastic_api_key="$ELASTIC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install opentelemetry-kube-stack open-telemetry/opentelemetry-kube-stack \
  --namespace opentelemetry-operator-system \
  --values 'https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v9.5.5/deploy/helm/edot-collector/kube-stack/managed_otlp/values.yaml' \
  --version '0.16.0' \
  --set 'collectors.daemon.config.processors.resource\/onboarding_id.attributes[0].action=upsert' \
  --set 'collectors.daemon.config.processors.resource\/onboarding_id.attributes[0].key=onboarding.id' \
  --set "collectors.daemon.config.processors.resource\\/onboarding_id.attributes[0].value=$ONBOARDING_ID" \
  --set 'collectors.daemon.config.service.pipelines.logs\/node.processors[9]=resource/onboarding_id' \
  --set 'collectors.daemon.config.service.pipelines.metrics\/node\/otel.processors[9]=resource/onboarding_id'

kubectl -n opentelemetry-operator-system rollout status deployment --timeout=300s || true

# 4. OTel demo (replicas etc. live in otel-demo-values.yaml)
kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
  --namespace otel-demo \
  --values "$HERE/otel-demo-values.yaml"

kubectl -n otel-demo get pods -o wide
echo
echo "Open the app with: kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080"
