# OTel demo on kind (3 workers) -> Elastic Serverless

Files:
- `kind-otel.yaml`: 1 control plane + 3 worker nodes.
- `otel-demo-values.yaml`: Helm values for the demo (replicas, collector config, disabled bundled backends).
- `install.sh`: end-to-end install. Idempotent; re-run after editing the values file to apply changes.

## Use
```bash
export ELASTIC_OTLP_ENDPOINT='https://<project>.ingest.<region>.aws.elastic.cloud:443'
export ELASTIC_API_KEY='<api-key>'   # never commit this
./deploy/kind/install.sh
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```
Shop: http://localhost:8080 · Feature flags: /feature · Load generator: /loadgen

## Change replicas
Edit `components.<service>.replicas` in `otel-demo-values.yaml`, then re-run `install.sh`.
Keep stateful services (`postgresql`, `kafka`, `valkey-cart`, `flagd`) and `load-generator` at 1.

## Tear down
```bash
kind delete cluster --name otel-demo
```
