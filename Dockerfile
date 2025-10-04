# --- Builder ---
FROM node:22-alpine AS builder
WORKDIR /app

# Install build tools required by Prisma engines
RUN apk add --no-cache openssl

# Install deps
COPY package.json ./
RUN npm install

# Prisma schema & client
COPY prisma ./prisma
RUN npx prisma generate || true

# TS sources
COPY tsconfig.json ./tsconfig.json
COPY src ./src

# Build
RUN npm run build

# --- Runtime ---
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# System deps Prisma may need
RUN apk add --no-cache openssl

# Copy project artifacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/dist ./dist
COPY docker/entrypoint.sh ./entrypoint.sh

# Ensure entrypoint has correct line endings & is executable
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

EXPOSE 8080
ENV PORT=8080

# Use JSON-form ENTRYPOINT to avoid shell parsing issues
ENTRYPOINT ["./entrypoint.sh"]
