#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_dir"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID to the target Google Cloud project}"

GCP_REGION=${GCP_REGION:-us-central1}
GCP_REPOSITORY=${GCP_REPOSITORY:-resumelens}
GCP_SERVICE=${GCP_SERVICE:-resumelens-api}
IMAGE_TAG=${IMAGE_TAG:-$(git rev-parse --short HEAD)}
IMAGE_URI="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GCP_REPOSITORY}/${GCP_SERVICE}:${IMAGE_TAG}"

gcloud config set project "$GCP_PROJECT_ID"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com

if ! gcloud artifacts repositories describe "$GCP_REPOSITORY" \
  --location "$GCP_REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$GCP_REPOSITORY" \
    --repository-format docker \
    --location "$GCP_REGION" \
    --description "ResumeLens Case Study 4 images"
fi

gcloud builds submit . \
  --config cloud/gcp/cloudbuild.yaml \
  --substitutions "_IMAGE=${IMAGE_URI}"

gcloud run deploy "$GCP_SERVICE" \
  --image "$IMAGE_URI" \
  --region "$GCP_REGION" \
  --allow-unauthenticated \
  --port 8080 \
  --set-env-vars "PRODUCT_MODE=api,APP_VERSION=${IMAGE_TAG}" \
  --cpu 1 \
  --memory 1Gi \
  --min-instances 0 \
  --max-instances 1 \
  --concurrency 1 \
  --timeout 300

public_url=$(gcloud run services describe "$GCP_SERVICE" \
  --region "$GCP_REGION" \
  --format='value(status.url)')

printf '\nGCP Cloud Run deployment complete\n'
printf 'Image: %s\n' "$IMAGE_URI"
printf 'Public URL: %s\n' "$public_url"
