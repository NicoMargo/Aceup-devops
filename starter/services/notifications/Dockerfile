#syntax=docker/dockerfile:1
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/types/package.json packages/types/
COPY services/notifications/package.json services/notifications/

RUN npm ci

COPY packages/logger packages/logger
COPY packages/secrets packages/secrets
COPY packages/types packages/types
COPY services/notifications services/notifications

RUN npm run build -w @aceup/logger -w @aceup/secrets -w @aceup/types -w @aceup/notifications-service

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/types/package.json packages/types/
COPY services/notifications/package.json services/notifications/

RUN npm ci --omit=dev

COPY --from=build /app/packages/logger/dist packages/logger/dist
COPY --from=build /app/packages/secrets/dist packages/secrets/dist
COPY --from=build /app/packages/types/dist packages/types/dist
COPY --from=build /app/services/notifications/dist services/notifications/dist

USER node
EXPOSE 8082
CMD ["node", "services/notifications/dist/index.js"]
