// Runtime configuration for the frontend.
// Defaults target local development. In containers this file is regenerated
// at startup by docker-entrypoint.sh from HELLO_SERVICE_URL / PROFILE_SERVICE_URL.
window.__APP_CONFIG__ = {
  HELLO_SERVICE_URL: "http://localhost:3001",
  PROFILE_SERVICE_URL: "http://localhost:3002",
};
