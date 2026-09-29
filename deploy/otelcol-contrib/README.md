# otelcol-contrib test image

Builds a Collector image with the **contrib** NATS exporter (core publish)
compiled from a local `opentelemetry-collector-contrib` checkout, for testing
the donation PR against this cluster before it merges.

The exporter isn't in any released distribution and Collector components are
compiled in, so this uses the
[OpenTelemetry Collector Builder](https://github.com/open-telemetry/opentelemetry-collector-releases/tree/main/cmd/builder)
with `replace`s pointing at the working copy.

## Iterate

```sh
# 1. change code in the contrib checkout, then:
./build.sh                     # cross-builds linux/amd64, pushes an immutable tag
# 2. paste the printed image into clusters/minimal/config.yaml (apps.otelCollector.image)
# 3. commit -> ArgoCD rolls it out
```

Override `CONTRIB_DIR`, `OCB_VERSION`, or `REG` via env if needed. `OCB_VERSION`
and the component versions in `builder-config.yaml` must track the exporter's
collector dependency.

## Topology

This image is the **producer** (`otlp -> nats exporter -> otel_test`). The
**consumer** side (`natscore receiver -> Jaeger`) runs as a separate deployment
(`base/otel-collector/consumer-*.yaml`) on the stable standalone `natscore`
image, since that receiver isn't in contrib yet and the two collector versions
can't share one binary. They interoperate over NATS (subject `otel_test`,
stream `OTEL_TEST`). Collapse them into one image once the receiver lands in
contrib.
