# --- Builder ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
COPY public ./public
# Compile TS -> dist and copy public into dist for convenience
RUN npm run build && test -d dist || (echo "ERROR: dist/ not found after build" && ls -la && exit 1)
RUN cp -r public dist/public || true

# --- Runner ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/dist ./dist
# ship source admin public too (not strictly needed since in dist/public, but handy)
COPY --from=builder /app/public ./public

# Runtime prep (no chown/chmod on volumes to avoid EPERM on managed platforms)
ENV DATA_DIR=/app/data
EXPOSE 8080
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
CMD ["./entrypoint.sh"]
