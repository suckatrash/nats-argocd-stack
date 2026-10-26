# otelcol-contrib test image

Builds a Collector image with the **contrib** NATS exporter and receiver (core
NATS) compiled from a local `opentelemetry-collector-contrib` checkout, for
testing the donation PRs against this cluster before they merge.

The NATS components aren't in any released distribution and Collector components are
compiled in, so this uses the
[OpenTelemetry Collector Builder](https://github.com/open-telemetry/opentelemetry-collector-releases/tree/main/cmd/builder)
with `replace`s pointing at the working copy.

## Iterate

```sh
# 1. change code in the contrib checkout, then:
./build.sh                     # cross-builds linux/amd64, pushes an immutable tag
# 2. paste the printed image into clusters/minimal/config.yaml (apps.otelCollector.image)
#    and base/otel-collector/consumer-deployment.yaml
# 3. commit -> ArgoCD rolls it out
```

Override `CONTRIB_DIR`, `OCB_VERSION`, or `REG` via env if needed. `OCB_VERSION`
and the component versions in `builder-config.yaml` must track the NATS
components' collector dependency.

## Topology

Both deployments run this image and interoperate over NATS (subject
`otel_test`):

- **producer** `otel-collector`: `otlp -> nats exporter -> otel_test`
- **consumer** `otel-collector-consumer`: `nats receiver -> Jaeger`

The contrib receiver is core NATS only for now, so the consumer subscribes to
`otel_test` directly (at-most-once). The `OTEL_TEST` stream still captures the
subject for inspection; move the consumer back to a durable JetStream consumer
once JetStream lands in the contrib receiver.
