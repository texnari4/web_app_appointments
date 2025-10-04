# --- Build ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# System deps (OpenSSL already present in bookworm)
COPY package.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate || true

COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public
RUN npm run build

# --- Runtime ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

CMD ["./entrypoint.sh"]
