# --- Builder ---
FROM node:22-alpine AS builder
WORKDIR /app
# System deps for Prisma on Alpine
RUN apk add --no-cache openssl libc6-compat
COPY package.json ./
RUN npm install
COPY prisma ./prisma
# generate client so tsc can typecheck @prisma/client
RUN npx prisma generate || true
COPY tsconfig.json ./tsconfig.json
COPY src ./src
RUN npm run build

# --- Runtime ---
FROM node:22-alpine AS runner
WORKDIR /app
RUN apk add --no-cache openssl libc6-compat
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/dist ./dist
COPY public ./public
COPY docker/entrypoint.sh ./entrypoint.sh
# normalize line endings & make executable
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh
EXPOSE 8080
ENV NODE_ENV=production
CMD ["./entrypoint.sh"]
