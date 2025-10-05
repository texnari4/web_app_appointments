
# --- Builder ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Compile TS -> dist (fail early if dist didn't appear)
RUN npm run build && test -d dist || (echo "ERROR: dist/ not found after build" && ls -la && exit 1)

# --- Runtime ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Ensure data dir exists & is writable
RUN mkdir -p /app/data && chown -R node:node /app
USER node

ENV NODE_ENV=production
ENV PORT=8080
ENV DATA_DIR=/app/data

EXPOSE 8080
CMD ["node", "dist/index.js"]
