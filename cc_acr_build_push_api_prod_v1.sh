#!/usr/bin/env bash
set -euo pipefail

ACR_NAME="acrcolconnectprodfrc"
IMAGE="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
CONTEXT_DIR="${1:-.}"

echo "== ACR login =="
az acr login -n "$ACR_NAME" >/dev/null
echo "✅ Logged in to $ACR_NAME"

echo ""
echo "== Docker build: $IMAGE (context=$CONTEXT_DIR) =="
docker build -t "$IMAGE" "$CONTEXT_DIR"

echo ""
echo "== Docker push: $IMAGE =="
docker push "$IMAGE"

echo ""
echo "✅ Done: pushed $IMAGE"
echo "Rollback (git): git reset --hard HEAD~1"
