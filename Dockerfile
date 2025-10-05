# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

COPY package.json ./
RUN npm install --production=false

COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Ensure data dir exists at build (not required for runtime but OK)
RUN mkdir -p /app/data

RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runtime
WORKDIR /app

COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Prepare data dir and permissions
RUN mkdir -p /app/data && chown -R node:node /app
ENV DATA_DIR=/app/data
ENV NODE_ENV=production

EXPOSE 8080
USER node
CMD ["node", "dist/index.js"]
