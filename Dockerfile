# v2.3.7 — runtime fix for Prisma engines on Railway
# Use Debian-based image (glibc) and install OpenSSL explicitly.
FROM node:22-bookworm-slim AS builder

ENV CI=true         PRISMA_CLIENT_ENGINE_TYPE=library         PRISMA_CLI_QUERY_ENGINE_TYPE=library

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \ 
    && rm -rf /var/lib/apt/lists/*

# Copy package manifests first to leverage cache
COPY package.json package-lock.json* ./
# Install all deps for build (dev deps included)
RUN npm ci || npm install

# Prisma client generation during build
COPY prisma ./prisma
RUN npx prisma generate || true

# App sources
COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public

# Build TypeScript
RUN npm run build

# --- Runtime ---
FROM node:22-bookworm-slim AS runner

ENV NODE_ENV=production         PORT=8080         PRISMA_CLIENT_ENGINE_TYPE=library         PRISMA_CLI_QUERY_ENGINE_TYPE=library

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \ 
    && rm -rf /var/lib/apt/lists/*

# Copy only what we need
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma

# Entrypoint
COPY docker/entrypoint.sh ./entrypoint.sh
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
