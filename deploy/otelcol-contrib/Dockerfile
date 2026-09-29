# Wraps a prebuilt (cross-compiled) linux/amd64 static collector binary in a
# distroless image. build.sh produces the binary on the host via ocb so the
# local module replaces resolve against the contrib checkout.
FROM gcr.io/distroless/static-debian12:nonroot
COPY _build/otelcol-nats-contrib /otelcol-nats
EXPOSE 4317 4318
ENTRYPOINT ["/otelcol-nats"]
CMD ["--config", "/etc/otelcol/config.yaml"]
