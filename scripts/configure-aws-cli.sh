#!/usr/bin/env bash
#
# Install and configure AWS CLI v2 (Step 3 of the project).
# On EC2 the preferred approach is an IAM instance role rather than static keys.
#
set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  echo "==> Installing AWS CLI v2"
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip -q awscliv2.zip
  sudo ./aws/install --update
  rm -rf awscliv2.zip aws
fi

echo "==> AWS CLI version:"
aws --version

# Interactive configuration (prompts for Access Key, Secret, region, output).
# Skip this on EC2 if you attached an IAM role to the instance.
echo "==> Running 'aws configure' (press enter to skip fields if using an IAM role)"
aws configure

echo "==> Verifying credentials:"
aws sts get-caller-identity
