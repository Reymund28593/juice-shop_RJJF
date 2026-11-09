#!/usr/bin/env bash
# Exports Xray evidence for the pushed image:
#   evidence/xray-scan.json        Xray scan result (vulnerabilities + violations)
#   evidence/sbom-cyclonedx.json   CycloneDX SBOM of the image
# The Xray export API returns a ZIP and only works once the image has been indexed and scanned,
# so each export is retried. Several request variants are tried per attempt (the accepted form of
# the component identifier differs between Xray versions). Every response is validated; the HTTP
# status and the server's answer are printed for each failed attempt.
# Env: TAG (required), IMAGE, DOCKER_DEV, OUT, RETRIES, WAIT. Requires a configured `jf`.
set -uo pipefail
: "${TAG:?TAG is required}"
IMAGE="${IMAGE:-juice-shop}"
REPO="${DOCKER_DEV:-juice-docker-dev-local}"
OUT="${OUT:-evidence}"
RETRIES="${RETRIES:-20}"
WAIT="${WAIT:-20}"
mkdir -p "$OUT"

IMG_PATH="${REPO}/${IMAGE}/${TAG}/manifest.json"

# Xray's own identifier for the image (docker://<name>:<tag>), looked up via the artifact summary.
resolve_component () {
  local resp id
  resp=$(jf xr curl -s -X POST api/v2/summary/artifact -H "Content-Type: application/json" \
         -d "{\"paths\":[\"default/${IMG_PATH}\"]}" 2>/dev/null || true)
  id=$(printf '%s' "$resp" | jq -r '.artifacts[0].general.component_id // empty' 2>/dev/null || true)
  [ -n "$id" ] && echo "component_id from Xray: $id" >&2
  printf '%s' "${id:-}"
}

# $1 = name  $2 = jq validation expression  $3... = request bodies (variants, tried in order)
export_zip () {
  local name="$1" check="$2" body f code
  shift 2
  local zip="$OUT/$name.zip" dir="$OUT/$name" resp="$OUT/$name.response"
  for i in $(seq 1 "$RETRIES"); do
    local v=0
    for body in "$@"; do
      v=$((v+1)); rm -rf "$dir"; rm -f "$zip" "$resp"
      code=$(jf xr curl -s -X POST api/v2/component/exportDetails \
               -H "Content-Type: application/json" -H "Accept: application/zip" \
               -d "$body" -o "$zip" -w '%{http_code}' 2>/dev/null || true)
      if [ -s "$zip" ] && unzip -tq "$zip" >/dev/null 2>&1; then
        mkdir -p "$dir"; unzip -oq "$zip" -d "$dir"
        while IFS= read -r f; do
          if jq -e "$check" "$f" >/dev/null 2>&1; then
            cp "$f" "$OUT/$name.json"
            echo "OK: $name ($(wc -c < "$OUT/$name.json") bytes, request variant $v)"
            return 0
          fi
        done < <(find "$dir" -type f -name '*.json')
        echo "$name variant $v: ZIP received but no valid content ($(find "$dir" -type f | wc -l) files)" >&2
      else
        echo "$name variant $v attempt $i/$RETRIES: HTTP ${code:-?}: $(head -c 300 "$zip" 2>/dev/null)" >&2
        mv "$zip" "$resp" 2>/dev/null || true
      fi
    done
    # a 404 on every variant is not an indexing delay, but retry a few times anyway
    sleep "$WAIT"
  done
  echo "FAILED to export $name after $RETRIES attempts (last server answers kept in $OUT/*.response)" >&2
  return 1
}

CID="$(resolve_component)"
NAMES=()
[ -n "$CID" ] && NAMES+=("$CID")
NAMES+=("docker://${IMAGE}:${TAG}" "${IMAGE}:${TAG}")
echo "Path: $IMG_PATH   Component candidates: ${NAMES[*]}"

scan_bodies=(); sbom_bodies=()
for n in "${NAMES[@]}"; do
  scan_bodies+=("{\"package_type\":\"docker\",\"component_name\":\"$n\",\"path\":\"$IMG_PATH\",\"vulnerabilities\":true,\"violations\":true,\"include_ignored_violations\":true,\"output_format\":\"json\"}")
  sbom_bodies+=("{\"package_type\":\"docker\",\"component_name\":\"$n\",\"path\":\"$IMG_PATH\",\"cyclonedx\":true,\"cyclonedx_format\":\"json\"}")
done
# variant without path
sbom_bodies+=("{\"package_type\":\"docker\",\"component_name\":\"${NAMES[0]}\",\"cyclonedx\":true,\"cyclonedx_format\":\"json\"}")

rc=0
export_zip "xray-scan" '(type=="array") or (type=="object" and (has("error") or has("errors")|not))' "${scan_bodies[@]}" || rc=1
export_zip "sbom-cyclonedx" '.bomFormat=="CycloneDX" and ((.components|length)>0)' "${sbom_bodies[@]}" || rc=1

echo "Evidence in $OUT/:"; ls -l "$OUT"/*.json "$OUT"/*.response 2>/dev/null
exit $rc
