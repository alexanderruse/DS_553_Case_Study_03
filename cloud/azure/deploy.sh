#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_dir"

AZURE_LOCATION=${AZURE_LOCATION:-eastus}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP:-resumelens-cs4-rg}
AZURE_CONTAINER_APP=${AZURE_CONTAINER_APP:-resumelens-api}
IMAGE_TAG=${IMAGE_TAG:-$(git rev-parse --short HEAD)}

build_context=$(mktemp -d)
cleanup() {
  rm -rf -- "$build_context"
}
trap cleanup EXIT

cp Dockerfile.cloud "$build_context/Dockerfile"
cp requirements-cloud.txt app.py "$build_context/"
cp -R src "$build_context/src"

az extension add --name containerapp --upgrade --only-show-errors
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --output none

# `containerapp up --source` creates or reuses an environment and registry,
# builds the temporary API-only Docker context, and configures public ingress.
az containerapp up \
  --name "$AZURE_CONTAINER_APP" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --source "$build_context" \
  --ingress external \
  --target-port 8080 \
  --env-vars "PRODUCT_MODE=api" "APP_VERSION=${IMAGE_TAG}"

az containerapp update \
  --name "$AZURE_CONTAINER_APP" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --min-replicas 0 \
  --max-replicas 1 \
  --output none

fqdn=$(az containerapp show \
  --name "$AZURE_CONTAINER_APP" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn \
  --output tsv)

printf '\nAzure Container Apps deployment complete\n'
printf 'Public URL: https://%s\n' "$fqdn"
