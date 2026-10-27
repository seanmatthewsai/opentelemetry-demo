#!/usr/bin/env bash
# Resume the demo: make sure the kind containers are up, restore replicas, port-forward localhost:8080.
set -euo pipefail
docker start $(docker ps -aq --filter "label=io.x-k8s.kind.cluster=otel-demo") >/dev/null 2>&1 || true
kubectl config use-context kind-otel-demo >/dev/null
F="${TMPDIR:-/tmp}/otel-demo-replicas.txt"
if [ -f "$F" ]; then
  while read -r name reps; do [ -n "$name" ] && kubectl -n otel-demo scale deploy "$name" --replicas="$reps"; done < "$F"
else
  helm upgrade --install otel-demo open-telemetry/opentelemetry-demo -n otel-demo --values "$(dirname "$0")/otel-demo-values.yaml"
fi
kubectl -n otel-demo rollout status deploy/frontend-proxy --timeout=600s
pkill -f "port-forward svc/frontend-proxy" 2>/dev/null || true
nohup kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080 >/tmp/otel-port-forward.log 2>&1 &
sleep 3
echo "Demo up: http://localhost:8080  (flags: /feature, load: /loadgen)"
