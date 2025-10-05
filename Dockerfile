# --- Builder ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci || npm install
COPY tsconfig.json ./
COPY src ./src
COPY public ./public
RUN npm run build && test -d dist || (echo "ERROR: dist/ not found after build" && ls -la && exit 1)

# --- Runtime ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY docker/entrypoint.sh ./entrypoint.sh
RUN mkdir -p /app/data && chmod 777 /app/data && chmod +x ./entrypoint.sh && chown -R node:node /app
USER node
ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
