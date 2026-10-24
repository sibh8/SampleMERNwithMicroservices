# ---- helloService Dockerfile ----
# Lightweight production image for the Express "hello" microservice.
FROM node:20-alpine

# Create app directory
WORKDIR /usr/src/app

# Install dependencies first to leverage Docker layer caching
COPY package*.json ./
RUN npm install --omit=dev

# Copy application source
COPY . .

# Run as the built-in non-root "node" user for security
USER node

# helloService listens on PORT (default 3001)
ENV PORT=3001
EXPOSE 3001

# Simple container healthcheck hitting the /health endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

CMD ["node", "index.js"]
