# --- Build stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

COPY package.json ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
COPY public ./public
RUN mkdir -p /app/data

RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV DATA_DIR=/app/data

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# volume dir + permissions
RUN mkdir -p /app/data && chown -R node:node /app
USER node

EXPOSE 8080
CMD ["node","dist/index.js"]
