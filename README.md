# ResumeLens Case Study 3 - beginner deployment guide

This project adapts the professor's Case Study 3 starter into a reproducible stack
for the earlier ResumeLens product. It runs two independently monitored product
containers from one image:

- `api_product`: calls a Hugging Face hosted model.
- `local_product`: runs Qwen3-0.6B on CPU inside the container.

Prometheus scrapes each product's Python metrics on port 8000 and its required
Node Exporter metrics on port 9100. Grafana is provisioned automatically. An Nginx
gateway allows one ngrok tunnel to expose `/api/`, `/local/`, and `/grafana/`.

## What the Docker words mean

- **Dockerfile**: recipe for building the ResumeLens image.
- **Image**: saved, reproducible application environment.
- **Container**: a running copy of an image.
- **Docker Compose**: starts the five connected services together.
- **Port mapping**: connects one claimed shared-VM port to a container port.
- **Docker network**: lets Prometheus use names such as `api_product:8000`.

## Architecture

```text
Internet -> ngrok -> claimed gateway port -> Nginx
                                      |-> /api/     -> API product container
                                      |-> /local/   -> local product container
                                      `-> /grafana/ -> Grafana -> Prometheus

Prometheus -> api_product:8000   (Python metrics)
Prometheus -> api_product:9100   (Node Exporter)
Prometheus -> local_product:8000 (Python metrics)
Prometheus -> local_product:9100 (Node Exporter)
```

## Step 1 - finish class setup before running Docker

1. Put your **public** SSH key in the instructor's class sheet. Never upload the
   private key.
2. Claim at least five unused ports in one group-owned range.
3. Record your group number and the path to your private key.
4. Create a Docker Hub account and keep its username lowercase.

The lecture's SSH form is:

```bash
ssh -i /path/to/your_private_key -p 2222 groupXX@melnibone.wpi.edu
```

Replace `XX` and the key path. The private key stays on your computer.

## Step 2 - put this repository on the shared VM

Clone this repository's `local` branch on the shared VM:

```bash
git clone -b local git@github.com:alexanderruse/DS_553_Case_Study_03.git
cd DS_553_Case_Study_03
```

Alternatively, copy it from your Mac with `scp` through the same SSH endpoint.

## Step 3 - configure ports and secrets

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Assign five ports from your claimed range. If the gateway port is `10234`, set:

```text
COMPOSE_PROJECT_NAME=groupXX_resumelens
PUBLIC_GATEWAY_PORT=10234
PUBLIC_BASE_URL=http://localhost:10234
```

The unique Compose project name prevents your container and network names from
colliding with another group on the shared Docker daemon.

Set a real Grafana password and Hugging Face token. `.env` is ignored by Git.
Do not place the HF token in the public UI, Dockerfile, Compose file, screenshots,
or report.

## Step 4 - verify Docker and Compose

```bash
docker version
docker compose version
docker ps
docker compose config
```

`docker compose config` should resolve successfully and must not be pasted into a
report because it can display interpolated secrets.

## Step 5 - build the application image

```bash
docker compose build
docker images | grep resumelens
```

The first build downloads PyTorch and can take several minutes. Docker caches
unchanged layers. The Dockerfile installs Node Exporter before Python packages so
requirements changes do not reinstall the system package.

## Step 6 - start the complete stack

```bash
docker compose up -d
docker compose ps
docker compose logs --tail=100 api_product local_product prometheus grafana
```

The local model is downloaded only on its first review request and is retained in
a named Docker volume. Initial local inference will therefore be slower.

Run the included checks:

```bash
chmod +x scripts/*.sh scripts/*.py
scripts/validate_stack.sh
scripts/show_container_ips.sh
```

Enter the two product-container IP addresses in the class Google Sheet. Container
IPs can change after recreation; record them only after the final deployment.

## Step 7 - test both products

For temporary private access from your laptop, create an SSH tunnel. Replace the
five local/remote ports with your values:

```bash
ssh -N -i /path/to/key -p 2222 \
  -L 18080:localhost:YOUR_GATEWAY_PORT \
  -L 19090:localhost:YOUR_PROMETHEUS_PORT \
  -L 13000:localhost:YOUR_GRAFANA_PORT \
  groupXX@melnibone.wpi.edu
```

Then open:

- `http://localhost:18080/api/`
- `http://localhost:18080/local/`
- `http://localhost:19090/targets`
- `http://localhost:13000/grafana/`

Use only a synthetic or sanitized resume. Perform several successful reviews in
both products. Also create one safe validation failure in each product by leaving
the job description empty. This gives the failure metrics a visible data point
without changing credentials or disrupting another group.

## Step 8 - verify Prometheus

On the Prometheus Targets page, these four jobs must all be **UP**:

1. `resumelens_api_product` (`api_product:8000`)
2. `resumelens_api_node` (`api_product:9100`)
3. `resumelens_local_product` (`local_product:8000`)
4. `resumelens_local_node` (`local_product:9100`)

Take a screenshot showing all four targets and the time. The application exports
eight bounded-cardinality metrics: request totals, latency, in-progress reviews,
input size, output size, model calls, categorized errors, and build information.

## Step 9 - verify Grafana

Log in with the credentials from `.env`. Open **Dashboards -> ResumeLens ->
ResumeLens Case Study 3 Overview**. Confirm that the dashboard shows both product
labels and take screenshots after generating traffic. Include the visible time
range and legends.

Node Exporter inside a container does not automatically provide perfect
container-only resource accounting. State this limitation in the report; the
rubric specifically requires the package in each product container.

## Step 10 - install and authenticate ngrok on the shared VM

Follow the class download command or ngrok's Linux download page, placing the
binary in your own account. Authenticate once without committing the token:

```bash
ngrok config add-authtoken YOUR_TOKEN
```

Then start the one public tunnel:

```bash
scripts/start_ngrok.sh
```

The script writes the four resulting URLs to `evidence/public_urls.txt` and
restarts only Grafana so its subpath uses the public base URL. Test `/api/`,
`/local/`, and `/grafana/` from a phone with Wi-Fi disabled or another non-WPI
network. Put the two product URLs in the class sheet. Save a screenshot of the
Grafana public URL for the visualization rubric.

Stop the tunnel with:

```bash
scripts/stop_ngrok.sh
```

## Step 11 - push the application image to Docker Hub

```bash
docker login
docker compose push api_product
docker image inspect "$DOCKERHUB_USERNAME/resumelens-cs3:$IMAGE_TAG" \
  --format '{{index .RepoDigests 0}}'
```

Record the image tag, digest, and Git commit in the report. Do not push `.env` or
model-cache volumes.

## Step 12 - collect monitoring data for the LLM rubric item

First tunnel the Prometheus port to local port 19090, then either run from your
laptop with `PROMETHEUS_URL=http://127.0.0.1:19090`, or run on the server using the
claimed Prometheus port:

```bash
PROMETHEUS_URL=http://127.0.0.1:YOUR_PROMETHEUS_PORT \
  python scripts/collect_monitoring_snapshot.py
```

Use `docs/LLM_ANALYSIS_TEMPLATE.md`. Preserve:

1. The timestamped snapshot.
2. The complete LLM prompt.
3. The complete LLM response.
4. Your own action decision, including accepted/rejected recommendations and
   exact metric values supporting the decision.

## Step 13 - report and submission evidence

Work through `docs/RUBRIC_CHECKLIST.md`. The 2-3 page report should include group
members, Docker changes, both monitoring paths, public exposure, Grafana evidence,
challenges/future work, the LLM analysis, and the independent human decision.

## Common beginner commands

```bash
docker compose ps                         # What is running?
docker compose logs -f local_product      # Follow one service's logs
docker compose restart api_product        # Restart one service
docker compose exec local_product bash    # Debug inside one container
docker compose down                       # Stop/remove containers, keep data
docker compose down -v                    # Also deletes model/metrics/dashboard data
```

Do not run `docker compose down -v` unless you intentionally want to delete the
downloaded model and all stored Prometheus/Grafana data.

## What changed from the professor's starter

- Replaced the generic chatbot with ResumeLens resume/job comparison.
- Removed the browser-entered HF token; the API token is server-side only.
- Runs API and local modes as separate containers with separate labels/metrics.
- Corrected Prometheus targets from `localhost` to Docker service names.
- Added six useful runtime metric families plus errors/build information (eight total).
- Added persistent Prometheus storage and an automatically provisioned dashboard.
- Added a one-tunnel gateway for both products and Grafana.
- Improved Docker layer order, non-root execution, health checks, signal handling,
  restart policies, and secret exclusion.
