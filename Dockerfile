FROM python:3.11-slim

ARG DEPLOY_SHA
ENV DEPLOY_SHA=${DEPLOY_SHA}
RUN sh -lc "mkdir -p /app && printf \"%s\" \"$DEPLOY_SHA\" > /app/DEPLOY_SHA && chmod 0644 /app/DEPLOY_SHA"

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

# ---- CC: embed deploy sha ----
ARG DEPLOY_SHA=unknown
ENV DEPLOY_SHA=${DEPLOY_SHA}
RUN echo "${DEPLOY_SHA}" > /app/DEPLOY_SHA || true
