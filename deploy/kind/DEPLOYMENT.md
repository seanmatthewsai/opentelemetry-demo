# Deployment: OTel demo on local kind, shipping to Elastic Serverless

Owner: Sean Matthews. Source of truth for how the demo runs in this environment.
Fork: https://github.com/seanmatthewsai/opentelemetry-demo

## Environment

| Item | Value |
|---|---|
| Host | Mac mini, Docker (kind runs nodes as containers) |
| Cluster | kind cluster `otel-demo`: 1 control plane + 3 workers (`kind-otel.yaml`) |
| Demo namespace | `otel-demo` (Helm release `otel-demo`, chart `open-telemetry/opentelemetry-demo`) |
| Collector namespace | `opentelemetry-operator-system` (Helm release `opentelemetry-kube-stack`, chart `open-telemetry/opentelemetry-kube-stack` v0.16.0) |
| EDOT collector config | `elastic/elastic-agent` tag `v9.5.5`, `deploy/helm/edot-collector/kube-stack/managed_otlp/values.yaml` |
| Backend | Elastic Serverless (Observability), EU Central 1 (AWS), staging |
| Deployment environment attribute | `deployment.environment=otel-demo` |
| Onboarding id | `fd8f5cc7-21fc-46a5-b84d-2519c90d83ab` (`onboarding.id` resource attribute) |

## APIs and endpoints

| Purpose | Endpoint / API | Auth |
|---|---|---|
| Managed OTLP ingest (Elastic Serverless) | `$ELASTIC_OTLP_ENDPOINT` (OTLP over gRPC/HTTP) | `Authorization: ApiKey <key>`, key stored in the Kubernetes secret `elastic-secret-otel` |
| In-cluster gateway collector (demo -> EDOT) | `opentelemetry-kube-stack-gateway-collector.opentelemetry-operator-system:4317` (OTLP gRPC, in-cluster, no TLS) | none (cluster-internal) |
| Demo app (local) | `http://localhost:8080` via `kubectl port-forward svc/frontend-proxy 8080:8080` | none |
| Feature flags UI (fault injection) | `http://localhost:8080/feature` | none |
| Load generator UI | `http://localhost:8080/loadgen` | none |
| Kubernetes API | kind context `kind-otel-demo` | local kubeconfig |

Required variables for `install.sh`:

| Variable | Meaning |
|---|---|
| `ELASTIC_OTLP_ENDPOINT` | Managed OTLP ingest URL of the Elastic Serverless project |
| `ELASTIC_API_KEY` | API key for that project. Never commit it |

Both are written to the `elastic-secret-otel` Kubernetes secret (`elastic_otlp_endpoint`, `elastic_api_key`).

## Telemetry flow

```
demo services --OTLP--> demo otel-collector (otel-demo ns)
   --OTLP :4317--> EDOT gateway collector (opentelemetry-operator-system)
   --OTLP/HTTPS--> Elastic Serverless managed OTLP endpoint
EDOT daemon collectors (per node) also send node/pod logs and metrics.
```
Bundled Prometheus, Grafana, Jaeger and OpenSearch are disabled; Elastic is the only backend.

## Replicas (see `otel-demo-values.yaml`)

| Service | Replicas |
|---|---|
| frontend, cart, product-catalog | 3 |
| frontend-proxy, checkout, currency, payment, recommendation, shipping, ad | 2 |
| everything else (postgresql, kafka, valkey-cart, flagd, load-generator, ...) | 1 |

## Deploy

```bash
export ELASTIC_OTLP_ENDPOINT='https://<project>.ingest.<region>.aws.elastic.cloud:443'
export ELASTIC_API_KEY='<api-key>'
./deploy/kind/install.sh
kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080
```

Re-run `install.sh` after editing `otel-demo-values.yaml` to apply changes (it uses `helm upgrade --install`).

## Verify

```bash
kubectl get nodes                                  # 4 nodes Ready
kubectl -n opentelemetry-operator-system get pods  # EDOT collectors Running
kubectl -n otel-demo get pods -o wide              # replicas spread over 3 workers
```
In Kibana (Observability): check Services/APM for `frontend`, `cart`, `checkout`, etc., with environment `otel-demo`.

## Fault injection flags (flagd, `src/flagd/demo.flagd.json`)

Toggle from `/feature`. All default to `off`.

| Flag | Effect | Variants |
|---|---|---|
| adFailure | Ad service fails | off, on |
| adHighCpu | High CPU in ad service | off, on |
| adManualGc | Full manual GCs in ad service | off, on |
| aiRunawayAgent | Agent loops tool calls to its recursion limit | off, on |
| aiSlowResponse | Slow LLM responses in agent | off, 5sec, 10sec |
| cartFailure | Cart fails n% of the time | off, 10%..100% |
| cartMetricCardinalityOverflow | Trace id on cart latency metric to overflow SDK cardinality | off, on |
| emailMemoryLeak | Memory leak in email service | off, 1x..10000x |
| emitRawPii | Emit raw PII attributes from checkout/payment | off, on |
| failedReadinessProbe | Cart readiness probe fails | off, on |
| imageSlowLoad | Slow image loading in frontend | off, 5sec, 10sec |
| intlShippingSlowdown | Slow international shipping | off, 5sec, 10sec |
| kafkaConsumerDead | fraud-detection leaves the consumer group | off, on |
| kafkaQueueProblems | Throttled fraud-detection consumer, lag climbs | off, 1sec, 3sec, 5sec |
| loadGeneratorFloodHomepage | Floods the frontend with requests | off, on |
| paymentFailure | Payment charge fails n% | off, 10%..100% |
| paymentUnreachable | Payment unavailable | off, on |
| productCatalogFailure | Product catalog fails on a specific product | off, on |
| productCatalogLockContention | DB lock contention in product catalog | off, on |
| recommendationCacheFailure | Recommendation cache fails | off, on |

## Tear down

```bash
kind delete cluster --name otel-demo
```
