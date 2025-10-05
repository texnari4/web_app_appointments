# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# Install deps first to leverage Docker layer cache
COPY package.json package-lock.json* ./
RUN npm ci || npm i

# Project files
COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public

# Compile TS -> dist (fail early if dist didn't appear)
RUN npm run build && test -d dist || (echo "ERROR: dist/ not found after build" && ls -la && exit 1)

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app

# Copy built app and runtime files
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules

# Data dir (Railway volume should be mounted to /app/data)
RUN mkdir -p /app/data && chown -R node:node /app
USER node

EXPOSE 8080
CMD ["node", "dist/index.js"]
