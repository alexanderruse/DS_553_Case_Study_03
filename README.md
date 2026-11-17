# ResumeLens AI — Case Studies 3 and 4

ResumeLens is a Gradio resume-review application. The `case-study-4` branch
extends the Docker work from Case Study 3 with an **API-only cloud image** and
deployment scaffolding for GCP Cloud Run, Azure Container Apps, and AWS ECS
Fargate. Case Study 4 deploys only the API-based product; the local llama.cpp
product, Prometheus stack, Grafana, nginx, and ngrok configuration remain in
the repository as the Case Study 3 implementation.

Use synthetic or sanitized resumes for demonstrations. The Hugging Face token
is entered in the API product's password field for each request and is not
stored in the image or repository.

## Case Study 4 status

The cloud-neutral implementation is complete and locally validated, but no
claim is made that the three live cloud deployments are complete. Account
creation, billing/budget configuration, provider authentication, live resource
creation, public URL testing, class Google Sheet entries, and report evidence
must be completed by the group in its own cloud accounts.

### Implemented on this branch

- `Dockerfile.cloud` builds a non-root, API-only image without llama.cpp or
  Node Exporter. It exposes container port 8080 and includes a health check.
- `requirements-cloud.txt` contains only dependencies required by the hosted
  API product.
- `app.py` honors the provider-supplied `PORT` environment variable, falling
  back to `APP_PORT` and then 7860 for older/local deployments.
- `cloud/gcp/` contains a Cloud Build configuration and a Cloud Run deployment
  script.
- `cloud/azure/` contains an Azure Container Apps source-deployment script.
- `cloud/aws/` contains an ECR build/push script and an ECS Fargate task
  definition template.
- `.github/workflows/deploy-azure.yml` tests, builds, publishes, deploys, and
  verifies the API product on Azure after the required secret and repository
  variables have been configured.
- `tests/test_cloud_deployment.py` statically validates the cloud image and
  provider scaffolding. The complete suite currently contains 49 tests.

Local validation completed on November 17, 2026:

- 49 tests passed in both the normal local test configuration and API mode.
- All three provider shell scripts passed Bash syntax validation.
- The AWS task-definition template parsed as valid JSON.
- `Dockerfile.cloud` built successfully.
- A live container smoke test served the application successfully with the
  nondefault provider-style setting `PORT=18080`.

These checks demonstrate that the portable image and deployment inputs are
internally consistent. They do not substitute for screenshots and successful
requests from actual GCP, Azure, and AWS deployments.

## Case Study 4 architecture and ports

Each provider runs the same API-only image:

```text
browser -> provider HTTPS URL -> managed container ingress -> ResumeLens:8080
                                                       -> Hugging Face Inference API
```

The Case Study 3 host-port range `2100--2110` is not used by the managed cloud
deployments. The cloud container normally listens on port 8080:

| Setting | Purpose | When to change it |
|---|---|---|
| `PORT` | Port assigned by a managed platform, especially Cloud Run | Do not hard-code it; the platform supplies it |
| `APP_PORT` | Explicit fallback port used by the image | Keep at 8080 unless a provider deployment uses a different target port |
| Azure `targetPort` | Routes Container Apps ingress to the application | Must match the application port; currently 8080 |
| ECS `containerPort` | Port targeted by the ECS service/load balancer | Must match the application port; currently 8080 |
| `METRICS_PORT` | Internal Python Prometheus endpoint | Defaults to 8000; it is not publicly exposed by the cloud scaffold |

If port 8080 is changed, update `Dockerfile.cloud`, the Azure workflow and
deployment script, the Cloud Run `--port` argument, the ECS task definition,
health checks, and any load-balancer target group together. A provider's public
HTTPS port remains managed by that provider.

## Local cloud-image validation

From the repository root:

```bash
docker build -f Dockerfile.cloud -t resumelens-api:cs4 .
docker run --rm -p 8080:8080 \
  -e PRODUCT_MODE=api \
  -e APP_PORT=8080 \
  resumelens-api:cs4
```

Open <http://localhost:8080>, enter a personal Hugging Face inference token,
and test with a synthetic resume. For code-only validation:

```bash
uv sync --locked
uv run --locked python -m pytest -q
PRODUCT_MODE=api uv run --locked python -m pytest -q
```

## Provider setup and values still required

### GCP Cloud Run

Before running the script, the group must create a GCP account/project, attach
billing, create a budget with alerts, install/authenticate `gcloud`, and select
the desired region.

```bash
gcloud auth login
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"       # change if the group selects another region
./cloud/gcp/deploy.sh
```

The script enables Cloud Run, Artifact Registry, and Cloud Build; creates the
Artifact Registry repository when needed; builds the image; deploys one public
Cloud Run service; and prints its URL. The project ID and region are deliberately
not committed because they belong to the group's account.

### Azure Container Apps

The group must create an Azure account/subscription, configure a Cost Management
budget, authenticate the Azure CLI, and choose globally valid resource names.

```bash
az login
export AZURE_LOCATION="eastus"
export AZURE_RESOURCE_GROUP="resumelens-cs4-rg"
export AZURE_CONTAINER_APP="resumelens-api"
./cloud/azure/deploy.sh
```

The manual script can create the resource group and deploy the source. The
GitHub Action additionally requires these repository settings:

| GitHub setting | Kind | Required value |
|---|---|---|
| `AZURE_DEPLOY_ENABLED` | Repository variable | Leave unset/false during setup; set to `true` when the resources and credentials below are ready |
| `AZURE_CREDENTIALS` | Environment/repository secret | Azure service-principal credential JSON; never commit it |
| `AZURE_ACR_NAME` | Repository variable | Existing Azure Container Registry name, without `.azurecr.io` |
| `AZURE_CONTAINER_APP_NAME` | Repository variable | Target Container App name |
| `AZURE_RESOURCE_GROUP` | Repository variable | Resource group containing the cloud resources |

The service principal must have enough access to push to the registry and
create/update the Container App. Until `AZURE_DEPLOY_ENABLED=true`, branch
pushes run the tests but deliberately skip Azure login, build, deployment, and
verification. The workflow does not need a Hugging Face token because users
enter their own token in the UI.

### AWS ECS Fargate

The group must create an AWS account, enable AWS Budgets alerts, authenticate
the AWS CLI, and select a region.

```bash
aws configure
export AWS_REGION="us-east-1"
./cloud/aws/build-and-push.sh
```

The script creates/reuses an ECR repository and pushes an amd64 image. AWS still
requires account-specific infrastructure: an ECS task execution role, CloudWatch
log group, VPC/subnets, security groups, ECS cluster/service, Application Load
Balancer, target group, and public listener. Replace `<AWS_ACCOUNT_ID>`,
`<AWS_REGION>`, and `<IMAGE_TAG>` in a generated copy of
`cloud/aws/task-definition.json`; do not commit a rendered file containing
account identifiers. The load balancer target port and health check must remain
consistent with container port 8080.

## GitHub Actions behavior

Two workflows run on `case-study-4`:

- `Tests` performs the repository test suite without deploying anything.
- `Deploy API product to Azure Container Apps` first runs the tests, then logs
  into Azure, builds/pushes the image, deploys the Container App, and verifies
  its public URL when `AZURE_DEPLOY_ENABLED=true`. Otherwise it reports that
  deployment is disabled and exits successfully after testing.

If **Run tests** fails, Azure login has not happened yet, so the cause is a test
or workflow-environment problem rather than missing Azure credentials. If
**Log in to Azure** fails after the tests pass, check `AZURE_CREDENTIALS`. If
the build/deploy step fails, check the three repository variables, service
principal permissions, ACR existence, resource names, region, and quota.

## Case Study 4 rubric checklist

| Rubric requirement | Code status | Evidence/action still required |
|---|---|---|
| GCP account (3) | Not representable in code | Create account/project and capture evidence |
| GCP cost monitoring (3) | Pending manual setup | Configure budget/alerts and screenshot them |
| GCP API deployment (10) | Script/image ready | Deploy, test a real request, and document changes |
| GCP Sheet URL (4) | Pending live deployment | Enter external URL and screenshot the row |
| Azure account (3) | Not representable in code | Create/verify subscription and capture evidence |
| Azure cost monitoring (3) | Pending manual setup | Configure budget/alerts and screenshot them |
| Azure API deployment (10) | Script/image ready | Deploy, test a real request, and document changes |
| Azure Sheet URL (4) | Pending live deployment | Enter external URL and screenshot the row |
| AWS account (3) | Not representable in code | Create account and capture evidence |
| AWS cost monitoring (3) | Pending manual setup | Configure AWS Budget/alerts and screenshot them |
| AWS API deployment (10) | Image/task scaffold ready | Provision ECS/ALB, test, and document changes |
| AWS Sheet URL (4) | Pending live deployment | Enter load-balancer URL and screenshot the row |
| Project report (25) | Not completed by this scaffold | Names; three setup sections; challenges; full LLM prompt/model/response; provider decision |
| GitHub Action (15) | Workflow implemented | Configure Azure settings and retain a successful automatic deployment run |
| Vertex AI extra credit (+10) | Not implemented | Add Vertex inference, sample request/response, tests, and report documentation if attempted |

For every live provider deployment, retain the commit hash, budget screenshot,
deployment/revision screenshot, public URL, successful synthetic request and
response, relevant logs, and the completed Google Sheet row. Budgets are alerts,
not guaranteed hard spending caps; remove billable resources after grading if
they are no longer needed.

See `cloud/README.md` and each provider subdirectory for shorter command-focused
instructions.

Current implementation references:

- [GCP `gcloud run deploy` reference](https://docs.cloud.google.com/sdk/gcloud/reference/run/deploy)
- [Azure Container Apps deployment action](https://github.com/Azure/container-apps-deploy-action/blob/main/README.md)
- [AWS ECS task definitions for Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html)

## Case Study 3 reference

For Case Study 3, ResumeLens ships as **two products built from one image**,
each in its own container on the shared VM:

| Product | `PRODUCT_MODE` | Models (primary → backup) | HF token |
|---|---|---|---|
| API-based | `api` | `openai/gpt-oss-20b` → `zai-org/GLM-5.3-Flash` (Hugging Face Inference API) | Typed into the web UI per request |
| Locally executed | `local` | Qwen3 0.6B Q4_K_M (`unsloth/Qwen3-0.6B-GGUF`) → LFM2.5 1.2B QAD-Q4_0 (`LiquidAI/LFM2.5-1.2B-Instruct-GGUF`), run with llama.cpp on the container CPU | Not needed |

Both Case Study 3 containers also run Prometheus Node Exporter (container port 9100) and
expose application metrics with `prometheus_client` (container port 8000).
Prometheus, Grafana, an nginx gateway and an optional ngrok tunnel run as
separate containers.

## Architecture and ports

The shared VM only allows host ports **2100–2110**. Container ports stay standard.

```
internet ──ngrok──▶ gateway:8080 (host 2100) ─┬─ /api/     ▶ api_product:7860
                                              ├─ /local/   ▶ local_product:7860
                                              └─ /grafana/ ▶ grafana:3000
prometheus:9090 (host 2103) scrapes api_product:{8000,9100}, local_product:{8000,9100}
grafana reads prometheus over the compose network
```

| Host port | Container | Purpose |
|---|---|---|
| 2100 | gateway → 8080 | Landing page plus `/api/`, `/local/` and `/grafana/`. The ngrok target. |
| 2101 | api_product → 7860 | API product UI (direct) |
| 2102 | local_product → 7860 | Local product UI (direct) |
| 2103 | prometheus → 9090 | Prometheus UI / query API |
| 2104 | grafana → 3000 | Grafana (direct; served under `/grafana/`) |
| 2105 / 2106 | api_product → 8000 / 9100 | Python metrics / Node Exporter |
| 2107 / 2108 | local_product → 8000 / 9100 | Python metrics / Node Exporter |
| 2109 | ngrok → 4040 | ngrok inspector API (127.0.0.1 only) |
| 2110 | — | Spare |

Each value can be overridden in `.env`. `BIND_ADDRESS` (default `0.0.0.0`)
controls whether the ports are reachable from the VM network or only from
the VM itself (`127.0.0.1`).

## Deploying on the shared VM

```bash
git clone <this repository> resumelens && cd resumelens
cp .env.example .env && chmod 600 .env
nano .env        # Compose project, Grafana password, ngrok, and optional image repository
scripts/up.sh    # supports docker compose and legacy docker-compose 1.29
scripts/validate_stack.sh
scripts/show_container_ips.sh
```

`scripts/up.sh` builds the image, starts all services, and prints the
URLs. When `NGROK_AUTHTOKEN` is set, it also writes them to
`evidence/public_urls.txt`. The first local review downloads the models into
the `model_cache` volume. The primary model is preloaded in the background at
startup.

Useful commands: `scripts/compose.sh ps`, `scripts/compose.sh logs -f local_product`,
`scripts/compose.sh down` (add `-v` to also delete the model cache and metrics
history).

### Legacy Docker Compose 1.29 compatibility

The VM uses the retired Python-based `docker-compose` 1.29 rather
than the current Docker CLI plugin. Every project script uses
`scripts/compose.sh`, which prefers `docker compose` and otherwise selects
`docker-compose`. Before a legacy build, `scripts/up.sh` removes only containers
with this project's Compose label, which prevents the legacy `ContainerConfig`
recreation failure with current Docker Engine image metadata. Named volumes are
preserved by default. Set `LEGACY_COMPOSE_RESET_VOLUMES=true` in `.env` only if
the model cache and Prometheus/Grafana history may also be deleted.
When Grafana needs its public ngrok URL applied, the legacy path removes and
freshly creates only the Grafana container instead of using the incompatible
Compose v1 force-recreation operation; its named data volume is still preserved.

From a laptop, an SSH tunnel reaches services that are bound to 127.0.0.1:

```bash
ssh -L 2100:127.0.0.1:2100 -L 2103:127.0.0.1:2103 <user>@<vm-host>
# then open http://localhost:2100/ and http://localhost:2103/targets
```

### Publishing with ngrok

The compose file has an `ngrok` service (official `ngrok/ngrok` image) that
tunnels to `gateway:8080`. One tunnel serves both products and Grafana:

1. Copy your authtoken from the ngrok dashboard into `NGROK_AUTHTOKEN` in `.env`.
2. Optionally set `NGROK_DOMAIN` to your free static domain so the URL stays
   the same across restarts.
3. Run `scripts/up.sh`. Public URLs are `<url>/api/`, `<url>/local/` and
   `<url>/grafana/`.

If `NGROK_AUTHTOKEN` is blank, the ngrok container logs
`ngrok disabled: NGROK_AUTHTOKEN not set` and exits cleanly. Stop the tunnel
with `scripts/compose.sh stop ngrok`. Without a static domain, `up.sh` recreates
Grafana with the discovered URL so its redirects use the public address.
Free ngrok URLs show a one-time browser warning page before the app loads.

### Docker Hub

Docker Hub configuration is optional. By default, Compose builds the local
image `resumelens-cs3:v1`, so deployment and cleanup commands do not require a
registry account. To publish the image, set this in `.env` first:

```dotenv
IMAGE_REPOSITORY=your-dockerhub-username/resumelens-cs3
IMAGE_TAG=v1
```

```bash
docker login
scripts/compose.sh build
scripts/compose.sh push api_product   # both products share the same image tag
set -a; source .env; set +a
docker image inspect --format '{{index .RepoDigests 0}}' "$IMAGE_REPOSITORY:$IMAGE_TAG"
```

## Modifications made for Docker

- **One image, two products.** `PRODUCT_MODE` picks the API or local product.
  Each container only offers its own two models, with primary → backup
  failover. The Case Study 1/2 cross-mode failover was removed.
- **Local inference runs 4-bit (Q4) GGUF models in-process** with
  `llama-cpp-python`, installed from prebuilt CPU wheels so the image needs no
  compiler. Case Study 2 used an external llama.cpp router instead. On 2 CPUs,
  Qwen3 0.6B Q4_K_M generates about 10 tokens/s and LFM2.5 1.2B Q4_0 about 6
  tokens/s. Unquantized bf16 transformers managed only about 1 token/s.
  Only one model is kept resident, and the container is limited to 3 GB of
  memory and 2 CPUs (`LOCAL_THREADS` matches the CPU limit). `llama_cpp` is
  imported lazily, so the API product never loads it. Qwen3 receives the
  `/no_think` switch so it answers directly.
- **The HF token comes from the UI.** The API product has a password field in
  the sidebar. The token is used for that request only, is never stored or
  logged, and is redacted from error messages. No container receives `HF_TOKEN`.
- **Subpath serving.** `ROOT_PATH` (`/api`, `/local`) lets Gradio generate
  correct asset URLs behind the nginx gateway. Grafana uses
  `GF_SERVER_SERVE_FROM_SUB_PATH`.
- **Container hardening.** The app binds `0.0.0.0` inside the container, runs
  as a non-root user under `tini`, and has a healthcheck and
  `no-new-privileges`. Secrets live only in the untracked `.env`.

## Monitoring

### Node Exporter: system metrics, container port 9100

The `Dockerfile` installs the Debian `prometheus-node-exporter` apt package.
`docker-entrypoint.sh` starts it with `--web.listen-address=":9100"` next to
the app, and the container exits if either process dies. Check it with
`scripts/compose.sh exec local_product curl -s localhost:9100/metrics | head`.
Node Exporter inside a container reports mostly host-level CPU and memory,
not per-container cgroup usage.

### prometheus_client (product metrics, container port 8000)

`app.py` defines the metrics and calls `start_http_server(8000)` at startup.
Every metric carries a `product` label (`api` or `local`):

| Metric | Type | Meaning |
|---|---|---|
| `resumelens_requests_total{result}` | Counter | Reviews by outcome (`success` / `error`) |
| `resumelens_request_duration_seconds` | Histogram | End-to-end review latency |
| `resumelens_in_progress_requests` | Gauge | Reviews currently running |
| `resumelens_input_characters` | Histogram | Resume + job description size |
| `resumelens_output_characters` | Histogram | Size of the generated feedback |
| `resumelens_model_calls_total{model,result}` | Counter | Every model attempt, including backup failovers |
| `resumelens_errors_total{error_type}` | Counter | `validation`, `missing_token`, `timeout`, `inference` |
| `resumelens_build_info{version,primary_model,backup_model}` | Gauge (1) | Deployed configuration |

`prometheus/prometheus.yml` scrapes all four targets (`api_product:8000`,
`api_product:9100`, `local_product:8000`, `local_product:9100`) every 15 s.
Grafana is provisioned with the Prometheus data source and the
**ResumeLens Case Study 3 Overview** dashboard (`grafana/dashboards/`).

`scripts/collect_monitoring_snapshot.py` saves a timestamped JSON/Markdown
snapshot of the key queries to `evidence/` for LLM analysis.

- Port range: **2100–2110**.
- Container IPs: the output of `scripts/show_container_ips.sh` (api_product, local_product).
- Public URLs: `evidence/public_urls.txt` (`/api/` and `/local/`).

## Development

Install uv, then run `uv sync --locked` and `uv run --locked python -m pytest -q`.
To run the local product outside Docker, run `uv sync --locked --group local`,
then `PRODUCT_MODE=local uv run app.py`. To run the API product, use
`PRODUCT_MODE=api uv run app.py` and enter a token in the UI. The UI listens
on port 7860, and metrics on `METRICS_PORT` (8000).
