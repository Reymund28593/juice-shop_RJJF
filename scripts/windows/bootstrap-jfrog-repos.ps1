# PowerShell version of bootstrap-jfrog-repos.sh
# Creates the Artifactory repository layout. Needs: jf CLI configured as admin (jf c add).
# Run:  powershell -ExecutionPolicy Bypass -File .\scripts\windows\bootstrap-jfrog-repos.ps1
$ErrorActionPreference = 'Stop'

$repos = [ordered]@{
  'juice-npm-remote'         = '{"rclass":"remote","packageType":"npm","url":"https://registry.npmjs.org","xrayIndex":true,"description":"npmjs proxy/cache - controlled entry point for third-party packages"}'
  'juice-npm-local'          = '{"rclass":"local","packageType":"npm","description":"internal npm packages"}'
  'juice-npm-virtual'        = '{"rclass":"virtual","packageType":"npm","repositories":["juice-npm-local","juice-npm-remote"],"defaultDeploymentRepo":"juice-npm-local","description":"single resolve endpoint for npm"}'
  'juice-docker-remote'      = '{"rclass":"remote","packageType":"docker","url":"https://registry-1.docker.io/","enableTokenAuthentication":true,"description":"Docker Hub proxy (base images)"}'
  'juice-gcr-remote'         = '{"rclass":"remote","packageType":"docker","url":"https://gcr.io","description":"gcr.io proxy (distroless runtime image)"}'
  'juice-docker-dev-local'   = '{"rclass":"local","packageType":"docker","dockerApiVersion":"V2","xrayIndex":true,"description":"CI pushes here (stage: dev)"}'
  'juice-docker-prod-local'  = '{"rclass":"local","packageType":"docker","dockerApiVersion":"V2","xrayIndex":true,"description":"only reachable through promotion (stage: prod)"}'
  'juice-docker-virtual'     = '{"rclass":"virtual","packageType":"docker","repositories":["juice-docker-dev-local","juice-docker-remote","juice-gcr-remote"],"defaultDeploymentRepo":"juice-docker-dev-local","description":"single docker endpoint for pull + push"}'
  'juice-generic-local'      = '{"rclass":"local","packageType":"generic","description":"SBOMs and Xray scan exports per image tag"}'
}

foreach ($key in $repos.Keys) {
  Write-Host ">> $key"
  # JSON goes through a temp file: avoids PowerShell quoting problems. ASCII = no BOM.
  $tmp = Join-Path $env:TEMP "$key.json"
  Set-Content -Path $tmp -Value $repos[$key] -Encoding ascii
  jf rt curl -s -X PUT "api/repositories/$key" -H "Content-Type: application/json" -d "@$tmp"
  Write-Host ""
  Remove-Item $tmp -ErrorAction SilentlyContinue
}
Write-Host "Done. Next in the UI: Xray indexed resources (+ builds), policies, watches. See README."
