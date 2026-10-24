#!/usr/bin/env bash
#
# Provision Jenkins + tooling on an Amazon Linux 2023 EC2 instance.
# Run as a user with sudo (e.g. ec2-user) after SSHing into the instance,
# or paste into the EC2 "User data" field at launch.
#
set -euo pipefail

echo "==> Updating packages"
sudo dnf update -y

echo "==> Installing Java 17 (required by Jenkins)"
sudo dnf install -y java-17-amazon-corretto

echo "==> Adding Jenkins repo and installing Jenkins"
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo dnf install -y jenkins
sudo systemctl enable --now jenkins

echo "==> Installing Docker and adding jenkins user to docker group"
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins
sudo usermod -aG docker ec2-user

echo "==> Installing git"
sudo dnf install -y git

echo "==> Installing AWS CLI v2"
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf awscliv2.zip aws

echo "==> Installing kubectl"
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

echo "==> Installing eksctl"
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
  | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin/eksctl

echo "==> Installing Helm"
curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> Restarting Jenkins so docker group membership applies"
sudo systemctl restart jenkins

echo ""
echo "==> Jenkins is installing. Retrieve the initial admin password with:"
echo "    sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo "==> Open Jenkins at: http://<EC2_PUBLIC_IP>:8080"
echo "==> Suggested plugins: Git, GitHub, Pipeline, Docker Pipeline, Pipeline: AWS Steps, Credentials Binding"
