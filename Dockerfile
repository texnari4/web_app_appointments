
# ---- Builder ----
FROM node:22-alpine AS builder
WORKDIR /app

# System deps for Prisma
RUN apk add --no-cache openssl libc6-compat

COPY package.json ./
RUN npm install

# Copy sources
COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY prisma ./prisma

# TypeScript build
RUN npm run build

# ---- Runner ----
FROM node:22-alpine AS runner
WORKDIR /app

# System deps for Prisma in runtime
RUN apk add --no-cache openssl libc6-compat

ENV NODE_ENV=production
ENV PORT=8080

# Copy artifacts from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY prisma ./prisma
COPY docker/entrypoint.sh ./entrypoint.sh

RUN chmod +x ./entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
