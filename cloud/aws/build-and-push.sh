#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_dir"

AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ECR_REPOSITORY=${AWS_ECR_REPOSITORY:-resumelens-api}
IMAGE_TAG=${IMAGE_TAG:-$(git rev-parse --short HEAD)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
image_uri="${registry}/${AWS_ECR_REPOSITORY}:${IMAGE_TAG}"

if ! aws ecr describe-repositories \
  --repository-names "$AWS_ECR_REPOSITORY" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr create-repository \
    --repository-name "$AWS_ECR_REPOSITORY" \
    --region "$AWS_REGION" >/dev/null
fi

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$registry"

# Explicit amd64 output works with the default x86 Fargate task even when this
# script is run from an Apple Silicon laptop.
docker buildx build \
  --platform linux/amd64 \
  --file Dockerfile.cloud \
  --tag "$image_uri" \
  --push .

printf '\nAWS ECR push complete\n'
printf 'Image: %s\n' "$image_uri"
printf 'Replace the placeholders in cloud/aws/task-definition.json before registering it.\n'
