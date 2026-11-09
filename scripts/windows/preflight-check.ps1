# PowerShell preflight check: local tools, Docker, JFrog connection and repositories.
# Run:  powershell -ExecutionPolicy Bypass -File .\scripts\windows\preflight-check.ps1 <name>.jfrog.io
param([string]$JfHost = $env:JF_HOST)
$script:fail = $false
function Ok($m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fail = $true }
function Need($cmd, [string[]]$verArgs = @('--version')) {
  if (Get-Command $cmd -ErrorAction SilentlyContinue) { Ok "${cmd}: $((& $cmd @verArgs 2>&1 | Select-Object -First 1))" }
  else { Bad "$cmd not installed" }
}

Write-Host "== Tools =="
Need git; Need gh; Need docker; Need jf; Need node; Need npm; Need kubectl @('version','--client')
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Bad "curl.exe missing (needed by 'jf rt curl')" } else { Ok "curl.exe found" }

Write-Host "== Docker =="
docker info *> $null
if ($LASTEXITCODE -eq 0) {
  Ok "Docker daemon reachable"
  $os = docker info --format '{{.OSType}}' 2>$null
  if ($os -eq 'linux') { Ok "Linux containers mode" } else { Bad "Docker is in Windows-containers mode: switch to Linux containers (tray icon)" }
} else { Bad "Docker daemon not reachable - start Docker Desktop and wait until it is running" }
docker buildx version *> $null
if ($LASTEXITCODE -eq 0) { Ok "BuildKit/buildx available" } else { Warn "buildx missing - update Docker Desktop" }
$freeGb = [math]::Round((Get-PSDrive -Name ($PWD.Drive.Name)).Free / 1GB)
if ($freeGb -ge 15) { Ok "free disk: $freeGb GB" } else { Warn "free disk only $freeGb GB (15+ recommended)" }
if ($PWD.Path -match 'OneDrive') { Warn "project folder is inside OneDrive - use C:\work instead" }

Write-Host "== package.json (run inside the Juice Shop fork) =="
if (Test-Path package.json) {
  $pkg = Get-Content package.json -Raw | ConvertFrom-Json
  Ok "engines.node = $($pkg.engines.node); installed node: $(node --version 2>$null)"
  foreach ($s in 'build:server','test:server') {
    if ($pkg.scripts.PSObject.Properties.Name -contains $s) { Ok "npm script '$s' exists" } else { Warn "npm script '$s' not found - adapt the workflow" }
  }
} else { Warn "package.json not found (not in the fork directory) - skipped" }

Write-Host "== JFrog connection =="
if (Get-Command jf -ErrorAction SilentlyContinue) {
  jf rt ping *> $null
  if ($LASTEXITCODE -eq 0) { Ok "Artifactory reachable via configured jf server" } else { Bad "jf rt ping failed - run: jf c add" }
  jf xr curl -s api/v1/system/ping *> $null
  if ($LASTEXITCODE -eq 0) { Ok "Xray reachable" } else { Warn "Xray not reachable (not in trial, or no permission?)" }
  foreach ($r in 'juice-npm-virtual','juice-docker-virtual','juice-docker-dev-local','juice-docker-prod-local','juice-generic-local') {
    $code = (jf rt curl -s -o NUL -w "%{http_code}" "api/repositories/$r" 2>$null) | Select-Object -Last 1
    if ("$code" -match '200$') { Ok "repo $r exists" } else { Warn "repo $r missing (run bootstrap-jfrog-repos.ps1)" }
  }
}
if ($JfHost) {
  try { Invoke-WebRequest -UseBasicParsing "https://$JfHost/artifactory/api/system/ping" | Out-Null; Ok "https://$JfHost reachable" }
  catch { Bad "cannot reach https://$JfHost" }
} else { Warn "no JF host given - host test skipped" }

Write-Host ""
if ($script:fail) { Write-Host "Preflight finished: fix the [FAIL] items first." -ForegroundColor Red; exit 1 }
else { Write-Host "Preflight finished: no blocking problems." -ForegroundColor Green }
