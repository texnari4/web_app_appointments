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
ENV PORT=8080
ENV DATA_DIR=/app/data

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY package.json ./package.json
COPY docker/entrypoint.sh ./entrypoint.sh

# ensure data dir exists and is writable even under non-root
RUN mkdir -p /app/data && chmod -R 777 /app && chmod +x ./entrypoint.sh

EXPOSE 8080
CMD ["./entrypoint.sh"]