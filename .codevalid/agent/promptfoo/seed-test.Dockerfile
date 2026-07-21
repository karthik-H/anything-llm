FROM node:22-bookworm-slim
ENV PROMPTFOO_DISABLE_TELEMETRY=1 \
    PROMPTFOO_DISABLE_UPDATE=1
WORKDIR /seed
RUN npm install -g promptfoo@0.121.17
COPY provider.yaml ai_seed_test.yaml ./
ENTRYPOINT ["promptfoo", "eval", "-c", "ai_seed_test.yaml"]
