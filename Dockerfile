# --- Builder stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# Install deps
COPY package.json package-lock.json* ./
RUN npm ci || npm install

# Copy sources
COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Build (produces /app/dist)
RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app

# App user & writable data dir (Railway volume can be mounted to /app/data)
RUN useradd -m -r appuser && mkdir -p /app/data && chown -R appuser:appuser /app

# Copy artifacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

USER appuser
ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "dist/index.js"]
