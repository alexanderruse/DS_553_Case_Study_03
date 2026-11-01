# Start here - your first Docker session

Do these in order. Stop when a step fails and read the matching README section.

## Before the shared VM

- [ ] Give the professor your **public** SSH key.
- [ ] Claim five unused ports in the class Google Sheet.
- [ ] Create a Docker Hub account.
- [ ] Obtain an ngrok account/token and a Hugging Face token.

## On the shared VM

```bash
# 1. Enter the project directory after cloning your repository.
cd resumelens-docker

# 2. Create the private configuration.
cp .env.example .env
nano .env
chmod 600 .env

# 3. Confirm Docker is available and check the resolved configuration.
docker version
docker compose version
docker compose config

# 4. Build and start all services.
docker compose build
docker compose up -d
docker compose ps

# 5. Validate both products and both kinds of monitoring.
chmod +x scripts/*.sh scripts/*.py
scripts/validate_stack.sh
scripts/show_container_ips.sh
```

Do not share the output of `docker compose config`; it can contain the expanded
Hugging Face token and Grafana password.

## From your laptop

Create an SSH tunnel using the exact command pattern in the README. Test:

- [ ] API product at `/api/`.
- [ ] Local product at `/local/`.
- [ ] Four Prometheus targets are UP.
- [ ] The Grafana dashboard loads and shows both products.

## Public evidence

Back on the shared VM:

```bash
ngrok config add-authtoken YOUR_TOKEN
scripts/start_ngrok.sh
```

- [ ] Test the API, local, and Grafana URLs from a non-WPI network.
- [ ] Enter both product URLs and both product-container IPs in the class sheet.
- [ ] Take the screenshots listed in `docs/RUBRIC_CHECKLIST.md`.
- [ ] Generate real traffic, collect a monitoring snapshot, and complete the LLM
      analysis plus your own human action decision.
- [ ] Push the application image to Docker Hub and record its tag/digest.

Read `README.md` for the explanation and exact commands behind each step.
