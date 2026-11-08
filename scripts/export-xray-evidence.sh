#!/usr/bin/env bash
# Exports (1) the Xray scan result as JSON and (2) a CycloneDX JSON SBOM for the pushed image.
# The Xray export API returns a ZIP; the scan must be finished, so we retry.
# Env: TAG (required), IMAGE, DOCKER_DEV, OUT. Requires a configured `jf` (setup-jfrog-cli).
set -euo pipefail
: "${TAG:?TAG is required}"
IMAGE="${IMAGE:-juice-shop}"
REPO="${DOCKER_DEV:-juice-docker-dev-local}"
OUT="${OUT:-evidence}"
SCAN_FORMAT="${SCAN_FORMAT:-json_full}"   # check the current Xray API docs if this value is rejected
mkdir -p "$OUT"

export_zip () {  # $1 = name, $2 = request body
  local name="$1" body="$2"
  for i in $(seq 1 30); do
    if jf xr curl -s -X POST api/v2/component/exportDetails \
         -H "Content-Type: application/json" -d "$body" -o "$OUT/$name.zip" \
       && unzip -tq "$OUT/$name.zip" >/dev/null 2>&1; then
      unzip -oq "$OUT/$name.zip" -d "$OUT/$name" && echo "OK: $name"
      return 0
    fi
    echo "Xray scan not ready yet ($i/30) - waiting 20s..."; sleep 20
  done
  echo "Failed to export $name" >&2
  return 1
}

COMPONENT="${IMAGE}:${TAG}"
PATH_IN_REPO="${REPO}/${IMAGE}/${TAG}/manifest.json"

export_zip "xray-scan" "$(cat <<JSON
{"package_type":"docker","component_name":"${COMPONENT}","path":"${PATH_IN_REPO}",
 "violations":true,"include_ignored_violations":true,"output_format":"${SCAN_FORMAT}"}
JSON
)"

export_zip "sbom-cyclonedx" "$(cat <<JSON
{"package_type":"docker","component_name":"${COMPONENT}","path":"${PATH_IN_REPO}",
 "cyclonedx":true,"cyclonedx_format":"json","vex":false}
JSON
)"

echo "Evidence written to $OUT/"
