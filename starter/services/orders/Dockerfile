#syntax=docker/dockerfile:1
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/types/package.json packages/types/
COPY packages/http-client/package.json packages/http-client/
COPY services/orders/package.json services/orders/

RUN npm ci

COPY packages/logger packages/logger
COPY packages/secrets packages/secrets
COPY packages/types packages/types
COPY packages/http-client packages/http-client
COPY services/orders services/orders

RUN npm run build -w @aceup/logger -w @aceup/secrets -w @aceup/types -w @aceup/http-client -w @aceup/orders-service

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/http-client/package.json packages/http-client/
COPY packages/types/package.json packages/types/
COPY services/orders/package.json services/orders/

RUN npm ci --omit=dev

COPY --from=build /app/packages/logger/dist packages/logger/dist
COPY --from=build /app/packages/secrets/dist packages/secrets/dist
COPY --from=build /app/packages/types/dist packages/types/dist
COPY --from=build /app/packages/http-client/dist packages/http-client/dist
COPY --from=build /app/services/orders/dist services/orders/dist

USER node
EXPOSE 8080
CMD ["node", "services/orders/dist/index.js"]
