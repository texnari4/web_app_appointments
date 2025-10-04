# -------- Builder --------
FROM node:22-alpine AS builder

# Needed by Prisma on alpine
RUN apk add --no-cache openssl libc6-compat

WORKDIR /app

COPY package.json ./
RUN npm install

COPY tsconfig.json ./tsconfig.json
COPY prisma ./prisma
COPY src ./src

# Build TypeScript (no prisma generate here)
RUN npm run build

# -------- Runner --------
FROM node:22-alpine AS runner

# Needed by Prisma on alpine
RUN apk add --no-cache openssl libc6-compat

ENV NODE_ENV=production

WORKDIR /app

# Copy runtime artifacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY package.json ./package.json

# Entrypoint orchestrates prisma + app start
COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]