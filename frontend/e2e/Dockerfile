# syntax=docker/dockerfile:1
# Keep the image tag in sync with @playwright/test in package.json.
FROM mcr.microsoft.com/playwright:v1.64.0-noble
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH CI=true
RUN corepack enable
WORKDIR /e2e
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
CMD ["pnpm", "test"]
