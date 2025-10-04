# --- Build stage --------------------------------------------------------------
FROM node:22-alpine AS builder
WORKDIR /app

RUN apk add --no-cache openssl libc6-compat

COPY package.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate || true

COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public

RUN npm run build

# --- Runtime stage ------------------------------------------------------------
FROM node:22-alpine AS runner
WORKDIR /app

RUN apk add --no-cache openssl libc6-compat

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public

COPY docker/entrypoint.sh ./entrypoint.sh
RUN sed -i 's/\r$//' ./entrypoint.sh && chmod +x ./entrypoint.sh

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["./entrypoint.sh"]
