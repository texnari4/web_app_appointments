# --- Builder ---
FROM node:22-alpine AS builder
WORKDIR /app

# OpenSSL for Prisma (binary deps)
RUN apk add --no-cache openssl

COPY package.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate || true

COPY tsconfig.json ./tsconfig.json
COPY src ./src

# Build
RUN npm run build

# --- Runtime ---
FROM node:22-alpine AS runner
WORKDIR /app

# OpenSSL for Prisma in runtime too
RUN apk add --no-cache openssl

# Copy built artifacts & runtime deps
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/dist ./dist
COPY public ./public

# Entrypoint
COPY docker/entrypoint.sh ./entrypoint.sh
# Normalize line endings & make executable
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080
CMD ["./entrypoint.sh"]
