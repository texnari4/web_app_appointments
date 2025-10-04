# ---------- Builder ----------
FROM node:22-alpine AS builder
WORKDIR /app

# System deps for Prisma binary
RUN apk add --no-cache openssl1.1-compat libc6-compat

COPY package.json ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate

COPY tsconfig.json ./tsconfig.json
COPY src ./src
RUN npm run build

# ---------- Runner ----------
FROM node:22-alpine AS runner
WORKDIR /app

RUN apk add --no-cache openssl1.1-compat libc6-compat

ENV NODE_ENV=production
ENV PORT=8080

# copy node_modules with prisma client
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY public ./public
COPY docker/entrypoint.sh ./entrypoint.sh

# fix LF just in case
RUN sed -i 's/\r$//' /app/entrypoint.sh && chmod +x /app/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]