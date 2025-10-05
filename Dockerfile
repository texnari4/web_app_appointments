# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# Install deps (use lockfile if present for reproducible builds)
COPY package.json package-lock.json* ./
RUN npm ci || npm i

# Copy config & sources
COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Compile TS -> dist (fail early if dist didn't appear)
RUN npm run build && test -d dist || (echo "ERROR: dist/ not found after build" && ls -la && exit 1)

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# App files
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json

# Install only production deps (uses package.json copied above)
RUN npm i --omit=dev --no-audit --no-fund

# Data dir & permissions for Railway volume at /app/data
RUN adduser --system --uid 1001 appuser         && mkdir -p /app/data         && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080
CMD ["node", "dist/index.js"]
