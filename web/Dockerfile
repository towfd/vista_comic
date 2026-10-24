# The web client as a built bundle behind nginx, so a deploy is a container
# rebuild rather than a dev server left open in a window.
# Build context is ./web (see docker-compose.yml at the repo root).

FROM node:22-alpine AS build
WORKDIR /app

# Dependencies first, for layer caching.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# `build` type-checks first: a bundle that does not type-check is not shipped.
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
