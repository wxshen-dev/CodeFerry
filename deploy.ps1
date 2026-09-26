[CmdletBinding()]
param(
    [switch]$NoRun,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $RepoRoot ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$ConfigDir = Join-Path $RepoRoot ".codeferry"
$ConfigPath = Join-Path $ConfigDir "config.yaml"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
    }
}

function Find-BasePython {
    $Python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($Python) {
        return $Python.Source
    }

    $Python = Get-Command python -ErrorAction SilentlyContinue
    if ($Python) {
        return $Python.Source
    }

    throw "Python 3.11 or newer was not found. Install Python from https://www.python.org/downloads/ and try again."
}

Push-Location $RepoRoot
try {
    Write-Host "[CodeFerry] Project: $RepoRoot" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        $BasePython = Find-BasePython
        Invoke-Checked -FilePath $BasePython -Arguments @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)")
        Write-Host "[CodeFerry] Creating virtual environment..." -ForegroundColor Cyan
        Invoke-Checked -FilePath $BasePython -Arguments @("-m", "venv", $VenvDir)
    }

    Invoke-Checked -FilePath $VenvPython -Arguments @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)")

    if (-not $SkipInstall) {
        & $VenvPython -c "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('pip') else 1)"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[CodeFerry] pip is missing; installing it into the virtual environment..." -ForegroundColor Cyan
            Invoke-Checked -FilePath $VenvPython -Arguments @("-m", "ensurepip", "--upgrade")
        }
        Write-Host "[CodeFerry] Installing dependencies..." -ForegroundColor Cyan
        Invoke-Checked -FilePath $VenvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip")
        Invoke-Checked -FilePath $VenvPython -Arguments @("-m", "pip", "install", "-e", $RepoRoot)
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
        @'
providers:
  - name: deepseek
    protocol: openai-compat
    base_url: https://api.deepseek.com
    model: deepseek-v4-flash
    api_key: ""

permission_mode: default
enable_fork: true
enable_verification_agent: true
teammate_mode: in-process
enable_coordinator_mode: false

worktree:
  symlink_directories:
    - node_modules
    - .venv
    - vendor
  stale_cleanup_interval: 3600
  stale_cutoff_hours: 24
'@ | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        Write-Host "[CodeFerry] Created $ConfigPath" -ForegroundColor Green
    }

    & $VenvPython -c "from codeferry.config import load_config; c=load_config(); raise SystemExit(0 if c.providers[0].resolve_api_key() else 1)"
    $HasApiKey = $LASTEXITCODE -eq 0

    if (-not $HasApiKey) {
        Write-Host "[CodeFerry] No API key was found in config.yaml or OPENAI_API_KEY." -ForegroundColor Yellow
        $SecureKey = Read-Host "Enter an API key for this run (press Enter to stop)" -AsSecureString
        $Credential = [System.Net.NetworkCredential]::new("", $SecureKey)
        $PlainKey = $Credential.Password
        if ([string]::IsNullOrWhiteSpace($PlainKey)) {
            throw "An API key is required before CodeFerry can start."
        }
        $env:OPENAI_API_KEY = $PlainKey
        $PlainKey = $null
    }

    Invoke-Checked -FilePath $VenvPython -Arguments @("-c", "from codeferry.config import load_config; from codeferry.client import create_client; c=load_config(); create_client(c.providers[0]); print('[CodeFerry] Configuration OK:', c.providers[0].name, c.providers[0].model)")

    Write-Host "[CodeFerry] Deployment completed." -ForegroundColor Green
    if (-not $NoRun) {
        Write-Host "[CodeFerry] Starting..." -ForegroundColor Cyan
        & $VenvPython -m codeferry
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
