#!/usr/bin/env bash
set -euo pipefail

BUILD_NAME="${JFROG_CLI_BUILD_NAME:-secure-pipeline}"
BUILD_NUMBER="${JFROG_CLI_BUILD_NUMBER:-1}"
OUT_DIR="evidence"
mkdir -p "$OUT_DIR"

echo "=== Exporting Xray scan results for build ${BUILD_NAME}/${BUILD_NUMBER} ==="

# 1. Build scan summary (JSON)
jf build-scan "$BUILD_NAME" "$BUILD_NUMBER" --format=json > "$OUT_DIR/xray-scan.json" || true

# 2. CycloneDX SBOM (via Xray)
echo "Trying to export CycloneDX SBOM..."
jf docker scan "${JF_URL}/${DOCKER_DEV}/${IMAGE}:${TAG}" --format=cyclonedx > "$OUT_DIR/sbom-cyclonedx.json" 2>/dev/null || \
jf rt curl -XGET "/xray/api/v1/component/exportDetails" \
  -H "Content-Type: application/json" \
  -d "{\"component_name\":\"${IMAGE}\",\"package_type\":\"docker\",\"version\":\"${TAG}\",\"format\":\"cyclonedx\"}" \
  > "$OUT_DIR/sbom-cyclonedx.json" || echo "SBOM export not available in this trial – using scan JSON instead"

echo "Evidence written to $OUT_DIR/"
ls -la "$OUT_DIR/"