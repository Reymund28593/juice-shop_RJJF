#!/usr/bin/env bash
# Preflight check for the local machine and the JFrog connection. Run before the first pipeline run.
# Usage: ./scripts/preflight-check.sh [JF_HOST]      e.g. mycompany.jfrog.io
# Works on Linux/macOS (Windows: WSL2). Exit code 1 if a mandatory check fails.
JF_HOST="${1:-${JF_HOST:-}}"
fail=0
ok()   { printf "  [ OK ] %s\n" "$1"; }
warn() { printf "  [WARN] %s\n" "$1"; }
bad()  { printf "  [FAIL] %s\n" "$1"; fail=1; }
need() { if command -v "$1" >/dev/null 2>&1; then ok "$1: $($1 --version 2>&1 | head -n1)"; else bad "$1 not installed"; fi; }
opt()  { if command -v "$1" >/dev/null 2>&1; then ok "$1 (optional) found"; else warn "$1 (optional) not installed"; fi; }

echo "== Tools =="
need git; need docker; need node; need npm; need jf; need curl; need unzip; need jq
opt kubectl; opt kind; opt minikube; opt cyclonedx-cli

echo "== Docker =="
if docker info >/dev/null 2>&1; then ok "Docker daemon reachable"; else bad "Docker daemon not reachable (start Docker Desktop / service)"; fi
if docker buildx version >/dev/null 2>&1; then ok "BuildKit/buildx available (needed for --secret)"; else bad "buildx missing - update Docker (>= 23)"; fi
free_gb=$(df -Pk . | awk 'NR==2{printf "%d", $4/1024/1024}')
[ "${free_gb:-0}" -ge 15 ] && ok "free disk: ${free_gb} GB" || warn "free disk only ${free_gb:-?} GB (15+ GB recommended)"
arch=$(uname -m); case "$arch" in arm64|aarch64) warn "ARM machine: pull/run the CI image with --platform linux/amd64";; *) ok "architecture $arch";; esac

echo "== Node version vs. package.json (run inside the Juice Shop fork) =="
if [ -f package.json ]; then
  eng=$(jq -r '.engines.node // "not specified"' package.json); ok "engines.node = $eng, installed: $(node -v)"
  for s in build:server test:server; do jq -e ".scripts[\"$s\"]" package.json >/dev/null 2>&1 && ok "npm script '$s' exists" || warn "npm script '$s' not found - adapt the workflow"; done
else warn "package.json not found (not in the fork directory) - skipped"; fi

echo "== JFrog connection =="
if command -v jf >/dev/null 2>&1; then
  if jf rt ping >/dev/null 2>&1; then ok "Artifactory reachable via configured jf server"; else bad "jf rt ping failed - run: jf c add"; fi
  if jf xr curl -s api/v1/system/ping >/dev/null 2>&1; then ok "Xray reachable"; else warn "Xray not reachable (feature missing in trial or no permission?)"; fi
  for r in juice-npm-virtual juice-docker-virtual juice-docker-dev-local juice-docker-prod-local juice-generic-local; do
    code=$(jf rt curl -s -o /dev/null -w "%{http_code}" "api/repositories/$r" 2>/dev/null | tail -c 3)
    [ "$code" = "200" ] && ok "repo $r exists" || warn "repo $r missing (run scripts/bootstrap-jfrog-repos.sh)"
  done
fi
if [ -n "$JF_HOST" ]; then
  curl -fsS -o /dev/null "https://$JF_HOST/artifactory/api/system/ping" && ok "https://$JF_HOST reachable" || bad "cannot reach https://$JF_HOST"
else warn "no JF_HOST given - skipped host reachability test"; fi

echo
[ $fail -eq 0 ] && echo "Preflight finished: no blocking problems." || { echo "Preflight finished: fix the [FAIL] items first."; exit 1; }
