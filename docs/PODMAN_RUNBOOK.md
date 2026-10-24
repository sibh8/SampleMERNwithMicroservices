# Podman Runbook: Bring the Stack Up and Running

A task-by-task checklist to build and run the full MERN stack locally using
**Podman** instead of Docker. Commands are PowerShell (Windows). Podman on Windows
runs a lightweight Linux VM (the "podman machine"), similar to Docker Desktop.

The app has four parts that must talk to each other:

| Service          | Image / build context          | Port  | Needs                         |
|------------------|--------------------------------|-------|-------------------------------|
| mongo            | docker.io/library/mongo:7      | 27017 | persistent volume             |
| hello-service    | ./backend/helloService         | 3001  | nothing                       |
| profile-service  | ./backend/profileService       | 3002  | mongo (via MONGO_URL)         |
| frontend         | ./frontend                     | 8080→80 | hello + profile (browser)   |

---

## Task 1: Install and start Podman

```powershell
# Install (choose one)
winget install RedHat.Podman
# or: choco install podman-cli

# One-time VM setup, then start it
podman machine init
podman machine start

# Verify
podman version
podman info
```

Done when: `podman version` prints client + server versions and `podman info`
shows the machine running.

---

## Task 2: Create a shared network

Compose auto-creates a network where services resolve each other by name. With
plain Podman you create it once so `profile-service` can reach `mongo` by hostname.

```powershell
podman network create mern-net
podman network ls
```

Done when: `mern-net` appears in the list.

---

## Task 3: Start MongoDB

```powershell
podman volume create mongo-data

podman run -d `
  --name mern-mongo `
  --network mern-net `
  -p 27017:27017 `
  -v mongo-data:/data/db `
  docker.io/library/mongo:7

# Confirm it is accepting connections
podman exec mern-mongo mongosh --quiet --eval "db.adminCommand('ping')"
```

Done when: the ping returns `{ ok: 1 }`.

---

## Task 4: Build the three images

Podman uses the same Dockerfiles with no changes.

```powershell
# from the repo root
podman build -t mern-hello-service:local ./backend/helloService
podman build -t mern-profile-service:local ./backend/profileService
podman build -t mern-frontend:local ./frontend

podman images | Select-String "mern-"
```

Done when: all three `mern-*:local` images are listed.

---

## Task 5: Run helloService

```powershell
podman run -d `
  --name mern-hello-service `
  --network mern-net `
  -e PORT=3001 `
  -p 3001:3001 `
  mern-hello-service:local

curl http://localhost:3001/
curl http://localhost:3001/health
```

Done when: `/` returns `{"msg":"Hello World"}` and `/health` returns `{"status":"OK"}`.

---

## Task 6: Run profileService

`MONGO_URL` points at the `mongo` container by its network alias. Note the host is
`mern-mongo` (the container name on the shared network), not `mongo`.

```powershell
podman run -d `
  --name mern-profile-service `
  --network mern-net `
  -e PORT=3002 `
  -e MONGO_URL="mongodb://mern-mongo:27017/profileDB" `
  -p 3002:3002 `
  mern-profile-service:local

curl http://localhost:3002/health
curl -Method POST http://localhost:3002/addUser -ContentType "application/json" -Body '{"name":"Ada","age":36}'
curl http://localhost:3002/fetchUser
```

Done when: `/health` is `OK`, addUser returns `User Added Successfully`, and
fetchUser returns a JSON array containing Ada. This proves MongoDB connectivity.

---

## Task 7: Run the frontend

The browser calls the backends directly, so these URLs must be host-reachable
(`localhost`), not container names.

```powershell
podman run -d `
  --name mern-frontend `
  --network mern-net `
  -e HELLO_SERVICE_URL="http://localhost:3001" `
  -e PROFILE_SERVICE_URL="http://localhost:3002" `
  -p 8080:80 `
  mern-frontend:local

curl http://localhost:8080/healthz
curl http://localhost:8080/config.js
```

Then open `http://localhost:8080` in a browser.

Done when: `/healthz` returns `ok`, `config.js` shows the two backend URLs, and the
page renders the Hello World heading plus the profile list.

---

## Task 8: Verify the whole stack

```powershell
podman ps
```

Done when: `mern-mongo`, `mern-hello-service`, `mern-profile-service`, and
`mern-frontend` are all `Up`. In the browser devtools Network tab, calls to
`localhost:3001` and `localhost:3002` return `200`.

Health status (Podman does not show `(healthy)` in `ps` like Compose does):

```powershell
podman healthcheck run mern-hello-service
podman healthcheck run mern-profile-service
podman inspect --format "{{.State.Health.Status}}" mern-frontend
```

---

## Task 9: Tear down

```powershell
podman rm -f mern-frontend mern-profile-service mern-hello-service mern-mongo
podman network rm mern-net
podman volume rm mongo-data   # omit to keep the data
```

---

## Alternative: podman-compose (uses the existing docker-compose.yml)

If you prefer a single command over Tasks 2-7, `podman-compose` reads the project's
`docker-compose.yml` directly.

```powershell
pip install podman-compose
podman-compose -f docker-compose.yml up --build -d
podman-compose ps
# ... same curl checks as Tasks 5-7 ...
podman-compose down
```

Caveat: `podman-compose` is a separate reimplementation. The `depends_on:
condition: service_healthy` used for `mongo` may not block as strictly as Docker
Compose does, so `profile-service` can start before Mongo is ready and then
reconnect. If you see it restart once, that is why. The explicit Tasks 2-7 avoid
this by starting Mongo first and confirming it is up before the backends.

---

## Quick task summary

1. Install + start Podman (`podman machine start`).
2. Create network `mern-net`.
3. Start MongoDB, confirm `ping` returns ok.
4. Build the 3 images from the existing Dockerfiles.
5. Run helloService, check `/` and `/health`.
6. Run profileService with `MONGO_URL`, add + fetch a user.
7. Run frontend, open `http://localhost:8080`.
8. `podman ps` shows all 4 up; browser calls return 200.
9. Tear down when finished.
