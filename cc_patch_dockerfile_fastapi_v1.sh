#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/c/Users/benme/Desktop/PLATEFORME TEST BIS ONE/colconnect_complet/backend"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)"
if [ -f Dockerfile ]; then
  cp -a Dockerfile "Dockerfile.bak.$ts"
  echo "✅ Backup Dockerfile -> Dockerfile.bak.$ts"
fi

has_req=0
has_pyproj=0
[ -f requirements.txt ] && has_req=1
[ -f pyproject.toml ] && has_pyproj=1

echo "== Detect deps =="
echo "requirements.txt: $has_req"
echo "pyproject.toml:   $has_pyproj"

if [ "$has_req" -eq 0 ] && [ "$has_pyproj" -eq 0 ]; then
  echo "❌ No requirements.txt and no pyproject.toml found in $ROOT" >&2
  echo "List files:" >&2
  ls -la >&2
  exit 1
fi

if [ "$has_req" -eq 1 ]; then
  echo "== Writing Dockerfile (pip + requirements.txt) =="
  cat > Dockerfile <<'DOCKER'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app

# System deps (minimal)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Install python deps first for better layer caching
COPY requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip && pip install -r /app/requirements.txt

# Copy app
COPY . /app

# Non-root (optional but good practice)
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Gunicorn (preferred) if installed, else fallback uvicorn
CMD sh -lc 'python -c "import gunicorn" >/dev/null 2>&1 && \
  exec gunicorn -k uvicorn.workers.UvicornWorker -w ${WORKERS:-2} -b 0.0.0.0:${PORT} ${APP_MODULE:-main:app} || \
  exec uvicorn ${APP_MODULE:-main:app} --host 0.0.0.0 --port ${PORT} --proxy-headers'
DOCKER
else
  echo "== Writing Dockerfile (poetry via pyproject.toml) =="
  cat > Dockerfile <<'DOCKER'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000 \
    POETRY_VERSION=1.8.3

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry
RUN python -m pip install --upgrade pip && pip install "poetry==${POETRY_VERSION}"

# Install deps (no dev)
COPY pyproject.toml /app/pyproject.toml
# poetry.lock may not exist
COPY poetry.lock /app/poetry.lock
RUN poetry config virtualenvs.create false \
 && poetry install --no-interaction --no-ansi --only main

COPY . /app

RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

CMD sh -lc 'python -c "import gunicorn" >/dev/null 2>&1 && \
  exec gunicorn -k uvicorn.workers.UvicornWorker -w ${WORKERS:-2} -b 0.0.0.0:${PORT} ${APP_MODULE:-main:app} || \
  exec uvicorn ${APP_MODULE:-main:app} --host 0.0.0.0 --port ${PORT} --proxy-headers'
DOCKER
fi

echo "== Dockerfile written =="
sed -n '1,120p' Dockerfile
echo "== Done =="
