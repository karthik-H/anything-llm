FROM postgres:16
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
COPY seed_test_cases ./seed_test_cases
