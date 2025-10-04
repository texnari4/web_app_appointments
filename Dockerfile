# --- Builder ---
FROM node:22-bookworm-slim AS builder

WORKDIR /app

COPY package.json ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
COPY public ./public

# Ensure data dir exists (not used at build, but good for layer)
RUN mkdir -p /app/data

RUN npm run build

# --- Runtime ---
FROM node:22-bookworm-slim AS runner

ENV NODE_ENV=production
ENV PORT=8080
ENV DATA_DIR=/app/data

WORKDIR /app

# Copy built app and minimal runtime deps
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Create data dir and ensure write access
RUN mkdir -p /app/data && chown -R node:node /app

USER node

COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

EXPOSE 8080
CMD ["./entrypoint.sh"]
