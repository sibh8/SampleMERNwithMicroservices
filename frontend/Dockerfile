# ---- Frontend Dockerfile (multi-stage) ----

# Stage 1: build the React app into static assets
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: serve the static build with nginx
FROM nginx:1.27-alpine

# Replace the default nginx site config with our SPA-friendly one
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the production build output
COPY --from=build /app/build /usr/share/nginx/html

# Entrypoint regenerates config.js from env vars, then starts nginx
COPY docker-entrypoint.sh /docker-entrypoint.d/40-runtime-config.sh
RUN chmod +x /docker-entrypoint.d/40-runtime-config.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

# nginx base image already defines an entrypoint that runs /docker-entrypoint.d/*
CMD ["nginx", "-g", "daemon off;"]
