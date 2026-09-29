#!/usr/bin/env bash
# Build & push a test collector image containing the CONTRIB NATS exporter
# (core publish) from a local opentelemetry-collector-contrib checkout.
#
# Each run cross-compiles a linux/amd64 collector binary via ocb (resolving the
# local module replaces in builder-config.yaml), wraps it in the distroless
# image, and pushes it under an immutable timestamp tag. It then prints the line
# to paste into clusters/<cluster>/config.yaml (apps.otelCollector.image);
# commit that change and ArgoCD rolls it out.
#
# Prereqs: go, docker buildx, gcloud authed to the Artifact Registry
# (gcloud auth configure-docker us-central1-docker.pkg.dev).
set -euo pipefail

# Must match the absolute replace paths in builder-config.yaml.
CONTRIB_DIR="${CONTRIB_DIR:-/Users/erik/projects/opentelemetry-collector-contrib}"
# Must match the collector component versions in builder-config.yaml.
OCB_VERSION="${OCB_VERSION:-v0.162.0}"
REG="${REG:-us-central1-docker.pkg.dev/erik-sandbox-408216/insights}"

cd "$(dirname "$0")"

if [ ! -d "$CONTRIB_DIR/exporter/natsexporter" ]; then
  echo "contrib checkout not found at $CONTRIB_DIR (set CONTRIB_DIR)" >&2
  exit 1
fi

TAG="nats-contrib-$(date +%Y%m%d%H%M%S)"
IMAGE="$REG/otelcol-nats:$TAG"

echo ">> building ocb binary (linux/amd64) against $CONTRIB_DIR"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go run "go.opentelemetry.io/collector/cmd/builder@$OCB_VERSION" --config builder-config.yaml

echo ">> verifying the binary is static"
file _build/otelcol-nats-contrib | grep -q 'statically linked' \
  || { echo "binary is not statically linked" >&2; exit 1; }

echo ">> building + pushing $IMAGE"
docker buildx build --platform linux/amd64 -t "$IMAGE" --push .

echo
echo "Pushed: $IMAGE"
echo "Set in clusters/minimal/config.yaml (apps.otelCollector.image), then commit:"
echo "    image: $IMAGE"
