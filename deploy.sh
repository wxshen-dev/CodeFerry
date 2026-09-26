#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_ROOT/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
CONFIG_DIR="$REPO_ROOT/.codeferry"
CONFIG_PATH="$CONFIG_DIR/config.yaml"
NO_RUN=0
SKIP_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --no-run) NO_RUN=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"
echo "[CodeFerry] Project: $REPO_ROOT"

if [[ ! -x "$VENV_PYTHON" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    BASE_PYTHON="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    BASE_PYTHON="$(command -v python)"
  else
    echo "Python 3.11 or newer was not found." >&2
    exit 1
  fi

  "$BASE_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || {
    echo "CodeFerry requires Python 3.11 or newer." >&2
    exit 1
  }
  echo "[CodeFerry] Creating virtual environment..."
  "$BASE_PYTHON" -m venv "$VENV_DIR"
fi

"$VENV_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || {
  echo "The existing virtual environment uses Python older than 3.11." >&2
  exit 1
}

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  if ! "$VENV_PYTHON" -c "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('pip') else 1)"; then
    echo "[CodeFerry] pip is missing; installing it into the virtual environment..."
    "$VENV_PYTHON" -m ensurepip --upgrade
  fi
  echo "[CodeFerry] Installing dependencies..."
  "$VENV_PYTHON" -m pip install --upgrade pip
  "$VENV_PYTHON" -m pip install -e "$REPO_ROOT"
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_PATH" <<'YAML'
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
YAML
  echo "[CodeFerry] Created $CONFIG_PATH"
fi

if ! "$VENV_PYTHON" -c 'from codeferry.config import load_config; c=load_config(); raise SystemExit(0 if c.providers[0].resolve_api_key() else 1)' >/dev/null 2>&1; then
  read -r -s -p "Enter an API key for this run (press Enter to stop): " CODEFERRY_KEY
  echo
  if [[ -z "$CODEFERRY_KEY" ]]; then
    echo "An API key is required before CodeFerry can start." >&2
    exit 1
  fi
  export OPENAI_API_KEY="$CODEFERRY_KEY"
  unset CODEFERRY_KEY
fi

"$VENV_PYTHON" -c "from codeferry.config import load_config; from codeferry.client import create_client; c=load_config(); create_client(c.providers[0]); print('[CodeFerry] Configuration OK:', c.providers[0].name, c.providers[0].model)"
echo "[CodeFerry] Deployment completed."

if [[ "$NO_RUN" -eq 0 ]]; then
  exec "$VENV_PYTHON" -m codeferry
fi
