FROM ghcr.io/shopify/toxiproxy:2.12.0
# base is FROM scratch (no shell/http client); add a static busybox just for the healthcheck
COPY --from=busybox:1.38-musl /bin/busybox /bin/busybox
COPY toxiproxy.json /config/toxiproxy.json
