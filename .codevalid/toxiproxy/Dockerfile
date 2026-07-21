FROM ghcr.io/shopify/toxiproxy:2.12.0
# Base is FROM scratch — only /toxiproxy and /toxiproxy-cli, no shell or HTTP client.
# Add a static (musl) busybox purely so the healthcheck can probe the admin API over HTTP.
COPY --from=busybox:1.38-musl /bin/busybox /bin/busybox
COPY toxiproxy.json /config/toxiproxy.json
