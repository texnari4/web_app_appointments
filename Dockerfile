# --- Builder ---
FROM node:22-alpine AS builder
WORKDIR /app

# OpenSSL for Prisma
RUN apk add --no-cache openssl

COPY package.json ./
RUN npm install

COPY prisma ./prisma
# Generate client even if DB is not reachable during build
RUN npx prisma generate || true

COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public

# Build
RUN npm run build

# --- Runtime ---
FROM node:22-alpine AS runner
WORKDIR /app

# OpenSSL for Prisma runtime
RUN apk add --no-cache openssl

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public
COPY docker/entrypoint.sh ./entrypoint.sh

# Normalize line endings and make executable
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

CMD ["./entrypoint.sh"]