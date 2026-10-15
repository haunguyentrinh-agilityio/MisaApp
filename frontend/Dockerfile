# syntax=docker/dockerfile:1

FROM node:24-alpine AS base
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
RUN corepack enable
WORKDIR /app

# ---- dev: Vite dev server with HMR (used by compose.dev.yaml) ----
FROM base AS dev
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
EXPOSE 5173
CMD ["pnpm", "dev"]

# ---- build ----
FROM base AS build
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# ---- runtime: static files + reverse proxy to the API ----
FROM nginx:1.29-alpine AS runtime
ARG SOURCE_COMMIT=dev
LABEL org.opencontainers.image.revision=$SOURCE_COMMIT
# The image's entrypoint renders /etc/nginx/templates/*.template into conf.d with envsubst.
ENV API_UPSTREAM=http://backend:8080 \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
