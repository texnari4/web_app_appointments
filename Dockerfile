# --- Builder stage ---
FROM node:22-bookworm-slim AS builder
WORKDIR /app

# Install deps
COPY package.json package-lock.json* ./
RUN npm install

# Build
COPY tsconfig.json ./tsconfig.json
COPY src ./src
COPY public ./public
RUN mkdir -p /app/data
RUN npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
# Copy runtime artifacts
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
# Prepare data dir and fix permissions for non-root
RUN mkdir -p /app/data && chown -R node:node /app
USER node

EXPOSE 8080
CMD ["node","dist/index.js"]