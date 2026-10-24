#!/usr/bin/env bash
# One-time creation of the ECR repositories used by this project.
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"

for repo in mern-frontend mern-hello-service mern-profile-service; do
  echo "==> Creating ECR repository: ${repo}"
  aws ecr create-repository \
    --repository-name "${repo}" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE \
    --region "${AWS_REGION}" \
    || echo "    (repository '${repo}' already exists, skipping)"
done
