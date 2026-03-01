#!/bin/bash
set -euo pipefail

ROOT="/mnt/c/Users/benme/Desktop/PLATEFORME TEST BIS ONE/colconnect_complet/backend"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)"

backup_if_exists() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -a "$f" "$f.bak.$ts"
    echo "✅ Backup: $f.bak.$ts"
  fi
}

backup_if_exists "Dockerfile"
backup_if_exists ".dockerignore"
backup_if_exists "entrypoint.sh"

cat > Dockerfile <<'DOCKER'
# syntax=docker/dockerfile:1.6
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000 \
    APP_MODULE=main:app \
    WORKERS=2

# OS deps (curl for healthcheck/debug; build-essential intentionally omitted for runtime)
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency manifests first (better layer cache)
COPY requirements*.txt /app/ 2>/dev/null || true
COPY pyproject.toml poetry.lock* /app/ 2>/dev/null || true

# Install deps
RUN python -m pip install --upgrade pip setuptools wheel && \
    if [ -f "requirements.txt" ]; then \
      pip install -r requirements.txt; \
    elif [ -f "pyproject.toml" ]; then \
      pip install "poetry==1.8.3" && \
      poetry config virtualenvs.create false && \
      poetry install --no-interaction --no-ansi --only main; \
    else \
      echo "❌ No requirements.txt or pyproject.toml found in build context." && exit 1; \
    fi

# Copy app
COPY . /app

EXPOSE 8000

# Optional: container-level healthcheck hitting /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

# Gunicorn (prod) with Uvicorn workers
# APP_MODULE is configurable at runtime: e.g. -e APP_MODULE="app.main:app"
CMD ["sh", "-lc", "exec gunicorn -k uvicorn.workers.UvicornWorker -w ${WORKERS} -b 0.0.0.0:${PORT} ${APP_MODULE} --access-logfile - --error-logfile - --log-level info --timeout 60"]
DOCKER

cat > .dockerignore <<'IGN'
.git
.gitignore
__pycache__/
*.pyc
*.pyo
*.pyd
*.swp
*.bak
*.log
*.sqlite3
.venv/
venv/
.env
.env.*
tests/
docs/
node_modules/
dist/
build/
IGN

# Ensure gunicorn + uvicorn exist even if requirements forgot them (soft add if requirements.txt exists)
if [ -f requirements.txt ]; then
  if ! grep -qiE '^(gunicorn|uvicorn)\b' requirements.txt; then
    backup_if_exists "requirements.txt"
    {
      echo ""
      echo "# Added by patch_gen_docker_prod_v1"
      echo "gunicorn==22.0.0"
      echo "uvicorn[standard]==0.30.6"
    } >> requirements.txt
    echo "✅ Added gunicorn/uvicorn to requirements.txt"
  fi
fi

echo "✅ Generated Dockerfile + .dockerignore (and ensured gunicorn/uvicorn if requirements.txt)."
echo "➡️ Next: build & push to ACR."
