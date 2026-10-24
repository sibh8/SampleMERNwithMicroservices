# Sample MERN with Microservices



For `helloService`, create `.env` file with the content:
```bash
PORT=3001
```

For `profileService`, create `.env` file with the content:
```bash
PORT=3002
MONGO_URL="specifyYourMongoURLHereWithDatabaseNameInTheEnd"
```

Finally install packages in both the services by running the command `npm install`.

<br/>
For frontend, you have to install and start the frontend server:

```bash
cd frontend
npm install
npm start
```

Note: This will run the frontend in the development server. To run in production, build the application by running the command `npm run build`

---

# Orchestration & Scaling: DevOps Deployment

This repository is containerized and deployed to AWS EKS with a full CI/CD and
observability stack. The sections below map to the graded project steps.

## Repository layout

```
.
├── backend/
│   ├── helloService/        # Express service (:3001) + Dockerfile
│   └── profileService/      # Express + Mongo service (:3002) + Dockerfile
├── frontend/                # React app + nginx Dockerfile + runtime config
├── docker-compose.yml       # Local full-stack testing
├── Jenkinsfile              # CI/CD pipeline (build -> ECR -> Helm -> SNS)
├── scripts/                 # AWS CLI, Jenkins install, ECR build/push (sh + ps1)
├── eks/                     # eksctl cluster config + create/delete scripts
├── helm/mern-stack/         # Helm chart for the whole stack (HPA, Ingress, Mongo)
├── monitoring/              # CloudWatch Container Insights, alarms, dashboard
├── chatops/                 # SNS topic + Lambda -> Slack/Teams notifier
└── docs/                    # Architecture, deployment guide, fork/sync guide
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system architecture + diagram
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — step-by-step deployment guide
- [docs/TESTING.md](docs/TESTING.md) — validation and testing guide (phase by phase)
- [docs/PODMAN_RUNBOOK.md](docs/PODMAN_RUNBOOK.md) — bring the stack up locally with Podman
- [docs/TEARDOWN.md](docs/TEARDOWN.md) — remove all AWS and local resources (cost control)
- [docs/FORK_AND_SYNC.md](docs/FORK_AND_SYNC.md) — fork and upstream sync

## Quick start (local)

```bash
docker compose up --build
# Frontend http://localhost:8080 | hello :3001 | profile :3002
```

## Quick start (AWS)

Follow [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). In short:
configure AWS CLI -> push images to ECR -> stand up Jenkins ->
create the EKS cluster -> `helm upgrade --install` -> enable monitoring + ChatOps.

> Before deploying, replace the placeholder account id `123456789012` in
> `Jenkinsfile` and `helm/mern-stack/values.yaml` with your AWS account id, and
> adjust the region if you are not using `ap-south-1`.
