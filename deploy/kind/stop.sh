#!/usr/bin/env bash
# Pause the demo: stop port-forward and scale all demo deployments to 0 (cluster and images are kept).
set -euo pipefail
pkill -f "port-forward svc/frontend-proxy" 2>/dev/null || true
pkill -f "otel-pf.sh" 2>/dev/null || true
mkdir -p "${TMPDIR:-/tmp}"
kubectl -n otel-demo get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.replicas}{"\n"}{end}' > "${TMPDIR:-/tmp}/otel-demo-replicas.txt"
kubectl -n otel-demo scale deploy --all --replicas=0
echo "Demo paused. Replica counts saved to ${TMPDIR:-/tmp}/otel-demo-replicas.txt"
