#!/usr/bin/env bash
# Creates the repository layout in the JFrog Platform (needs an admin-configured `jf` server: jf c add).
# Idempotent-ish: re-running updates existing repos with the same key (PUT may return an error if the repo exists,
# in that case use POST via the UI or delete first).
set -euo pipefail

put_repo () {  # $1 = key, $2 = json
  echo ">> $1"
  jf rt curl -s -X PUT "api/repositories/$1" -H "Content-Type: application/json" -d "$2"
  echo
}

# --- npm ---
put_repo RJjuice-npm-remote  '{"rclass":"remote","packageType":"npm","url":"https://registry.npmjs.org","xrayIndex":true,"description":"npmjs proxy/cache - controlled entry point for third-party packages"}'
put_repo RJjuice-npm-local   '{"rclass":"local","packageType":"npm","description":"internal npm packages"}'
put_repo RJjuice-npm-virtual '{"rclass":"virtual","packageType":"npm","repositories":["juice-npm-local","juice-npm-remote"],"defaultDeploymentRepo":"juice-npm-local","description":"single resolve endpoint for npm"}'

# --- docker ---
put_repo RJjuice-docker-remote '{"rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/","enableTokenAuthentication":true,"description":"Docker Hub proxy (base images)"}'
put_repo RJjuice-gcr-remote    '{"rclass":"remote","packageType":"docker","url":"https://gcr.io","description":"gcr.io proxy (distroless runtime image)"}'
put_repo RJjuice-docker-dev-local  '{"rclass":"local","packageType":"docker","dockerApiVersion":"V2","xrayIndex":true,"description":"CI pushes here (stage: dev)"}'
put_repo RJjuice-docker-prod-local '{"rclass":"local","packageType":"docker","dockerApiVersion":"V2","xrayIndex":true,"description":"only reachable through promotion (stage: prod)"}'
put_repo RJjuice-docker-virtual '{"rclass":"virtual","packageType":"docker","repositories":["juice-docker-dev-local","juice-docker-remote","juice-gcr-remote"],"defaultDeploymentRepo":"juice-docker-dev-local","description":"single docker endpoint for pull + push"}'

# --- generic (SBOM / scan evidence) ---
put_repo RJjuice-generic-local '{"rclass":"local","packageType":"generic","description":"SBOMs and Xray scan exports per image tag"}'

echo "Done. Next in the UI: Xray indexed resources (+ builds), policies, watches. See README."
