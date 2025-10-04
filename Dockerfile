# --- Builder ---
FROM node:22-alpine AS builder
WORKDIR /app

# System deps needed by Prisma on Alpine
RUN apk add --no-cache openssl

# Install only production deps first for better cache hits
COPY package.json ./
RUN npm install

# Prisma schema (optional at build time)
COPY prisma ./prisma
RUN npx prisma generate || true

# TS config & sources
COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public

# Build
RUN npm run build

# --- Runtime ---
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

# Bring build artifacts and runtime deps
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public

# Entrypoint
COPY docker/entrypoint.sh ./entrypoint.sh
# normalize line endings and make executable
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

CMD ["./entrypoint.sh"]
