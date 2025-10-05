# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
COPY public ./public
RUN mkdir -p /app/data
RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
# Ensure app dir is writable (volume will mount over /app/data)
RUN mkdir -p /app/data && chown -R node:node /app
EXPOSE 8080
CMD ["./entrypoint.sh"]
