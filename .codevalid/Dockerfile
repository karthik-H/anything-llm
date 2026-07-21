FROM node:22-bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        bash \
        netcat-openbsd \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first (cache layer independent of source)
COPY server/package.json server/yarn.lock ./server/

RUN cd server && yarn install --frozen-lockfile --ignore-scripts

# Copy all application source (includes prisma/schema.prisma)
COPY . .

# Codegen: generate Prisma client after schema is present, before any build step
RUN cd server && npx prisma generate

RUN mkdir -p /app/storage

ENV PORT=6713
ENV SERVER_PORT=6713
EXPOSE 6713

COPY .codevalid/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "server/index.js"]
