#!/usr/bin/env bash
#
# Build the three MERN images and push them to Amazon ECR.
# Creates the ECR repositories if they don't exist.
#
# Prerequisites: aws cli v2, docker, and valid AWS credentials.
#
# Usage:
#   AWS_REGION=ap-south-1 IMAGE_TAG=$(git rev-parse --short HEAD) ./scripts/ecr-build-push.sh
#
set -euo pipefail

# ----- Configuration (override via environment variables) -----
AWS_REGION="${AWS_REGION:-ap-south-1}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Resolve the account id from the current credentials
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# repo name  ->  build context (relative to repo root)
REPOS=(
  "mern-frontend:./frontend"
  "mern-hello-service:./backend/helloService"
  "mern-profile-service:./backend/profileService"
)

# Move to repo root (this script lives in ./scripts)
cd "$(dirname "$0")/.."

echo "==> Account: ${AWS_ACCOUNT_ID}  Region: ${AWS_REGION}  Tag: ${IMAGE_TAG}"

# ----- Authenticate Docker to ECR -----
echo "==> Logging in to ECR registry ${ECR_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# ----- Build, create repo, tag and push each image -----
for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"
  context="${entry##*:}"
  image="${ECR_REGISTRY}/${repo}"

  echo "==> Ensuring ECR repository '${repo}' exists"
  aws ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1 \
    || aws ecr create-repository \
         --repository-name "${repo}" \
         --image-scanning-configuration scanOnPush=true \
         --region "${AWS_REGION}" >/dev/null

  echo "==> Building ${repo} from ${context}"
  docker build -t "${repo}:${IMAGE_TAG}" "${context}"

  echo "==> Tagging and pushing ${image}:${IMAGE_TAG}"
  docker tag "${repo}:${IMAGE_TAG}" "${image}:${IMAGE_TAG}"
  docker tag "${repo}:${IMAGE_TAG}" "${image}:latest"
  docker push "${image}:${IMAGE_TAG}"
  docker push "${image}:latest"
done

echo "==> Done. Pushed images:"
for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"
  echo "    ${ECR_REGISTRY}/${repo}:${IMAGE_TAG}"
done
