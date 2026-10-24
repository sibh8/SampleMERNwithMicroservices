# ---- profileService Dockerfile ----
# Production image for the Express + MongoDB "profile" microservice.
FROM node:20-alpine

WORKDIR /usr/src/app

# Install dependencies first for better layer caching
COPY package*.json ./
RUN npm install --omit=dev

# Copy application source
COPY . .

# Run as non-root user
USER node

# profileService listens on PORT (default 3002)
ENV PORT=3002
EXPOSE 3002

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3002/health || exit 1

CMD ["node", "index.js"]
