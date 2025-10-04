# ---------- BUILD ----------
FROM node:22-alpine AS builder

WORKDIR /app
ENV CI=true
ENV NODE_ENV=development

COPY package.json ./
# COPY package-lock.json ./  # uncomment if you have it
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate

COPY tsconfig.json ./tsconfig.json
COPY src ./src
RUN npm run build

# ---------- RUNTIME ----------
FROM node:22-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma

COPY docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

ENV PORT=8080
EXPOSE 8080

STOPSIGNAL SIGINT

ENTRYPOINT ["./entrypoint.sh"]
CMD ["node", "dist/index.js"]
