#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Patch: E2E ACR cloud build -> push :prod -> VMSS redeploy
# with ACR refresh token docker login on each VM
# + Internal proofs + External tests + PASS/FAIL
#
# ID: CC_PATCH_E2E_ACR_BUILD_VMSS_REDEPLOY_PROOF_V1_20260303
# ==========================================================

RG="rg-colconnect-prod-frc"
ACR="acrcolconnectprodfrc"
IMAGE="colconnect-api"
TAG="prod"
IMG="${ACR}.azurecr.io/${IMAGE}:${TAG}"

VMSS="vmss-api-colconnect-prod"
NAME="colconnect-api"
PORT="8000"

DOCKERFILE="Dockerfile"

# optional: if repo has git, we inject DEPLOY_SHA build-arg for traceability
DEPLOY_SHA="e2e-$(date +%Y%m%d_%H%M%S)"

log() { printf "\n== %s ==\n" "$*"; }

log "Preconditions"
test -f "$DOCKERFILE" || { echo "❌ Dockerfile not found (run from backend repo root)"; exit 1; }
az account show -o table >/dev/null
echo "✅ Azure session OK"
echo "IMG=$IMG"
echo "DEPLOY_SHA=$DEPLOY_SHA"

log "Resolve VMs (VMSS Flexible instances)"
VMS="$(az vm list -g "$RG" --query "[?contains(name,'$VMSS')].name" -o tsv || true)"
[ -n "${VMS:-}" ] || { echo "❌ No VMs found containing '$VMSS' in RG=$RG"; az vm list -g "$RG" -o table | sed -n '1,120p'; exit 1; }
echo "$VMS" | sed 's/^/ - /'

log "ACR cloud build (no local docker) -> tag :prod"
az acr build -r "$ACR" -g "$RG" \
  -t "${IMAGE}:${TAG}" \
  --build-arg "DEPLOY_SHA=$DEPLOY_SHA" \
  . \
  | tee "run_acr_build_${IMAGE}_${TAG}_$(date +%Y%m%d_%H%M%S).log"

log "Fetch ACR refresh token (for docker login on VMs)"
TOKEN="$(az acr login -n "$ACR" --expose-token --query accessToken -o tsv)"
[ -n "${TOKEN:-}" ] || { echo "❌ Failed to get ACR token"; exit 1; }
echo "✅ Token acquired (not printed)."

log "Redeploy on each VM (docker login -> pull -> recreate -> local proof)"
PASS_INTERNAL=1

for VM in $VMS; do
  echo ""
  echo "=============================="
  echo "== VM: $VM =="
  echo "=============================="

  az vm run-command invoke -g "$RG" -n "$VM" \
    --command-id RunShellScript \
    --scripts @- <<'BASH' >"run_vm_${VM}_redeploy_proof_$(date +%Y%m%d_%H%M%S).log" || PASS_INTERNAL=0
set -eu

ACR="$ACR"
IMG="$IMG"
NAME="$NAME"
PORT="$PORT"
TOKEN="$TOKEN"

echo "== hostname/date =="
hostname || true
date -u || true

echo "== docker login to ACR (refresh token as password) =="
docker login "${ACR}.azurecr.io" -u "00000000-0000-0000-0000-000000000000" -p "\$TOKEN" >/dev/null 2>&1 || {
  echo "❌ docker login failed"
  exit 10
}
echo "✅ docker login ok"

echo "== pull image =="
docker pull "\$IMG" || { echo "❌ docker pull failed"; exit 11; }

echo "== preserve env (best effort) =="
ENVFILE="/tmp/cc_env_\$NAME.env"
rm -f "\$ENVFILE" || true
if docker inspect "\$NAME" >/dev/null 2>&1; then
  docker inspect "\$NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(PORT|APP_MODULE|WORKERS|MONGO|DB_|JWT_|ENV|LOG_|ALLOWED_|CORS|KEYVAULT|AZURE|APP_)=' \
    > "\$ENVFILE" || true
fi

echo "== recreate container =="
docker rm -f "\$NAME" >/dev/null 2>&1 || true

# If env file exists and non-empty, use it; else run with minimal env
if [ -s "\$ENVFILE" ]; then
  docker run -d --restart unless-stopped --name "\$NAME" \
    --env-file "\$ENVFILE" \
    -p "\$PORT:\$PORT" \
    "\$IMG" >/dev/null
else
  docker run -d --restart unless-stopped --name "\$NAME" \
    -e PORT="\$PORT" -e APP_MODULE="main:app" \
    -p "\$PORT:\$PORT" \
    "\$IMG" >/dev/null
fi

echo "✅ container started"

echo "== wait small warmup =="
sleep 2 || true

echo "== local proof (route presence) =="
# 1) openapi grep endpoints
HAS_DEPLOY="$(curl -sS -m 6 "http://127.0.0.1:\$PORT/openapi.json" | tr -d '\n' | grep -c '"/api/deploy"' || true)"
HAS_V1_DEPLOY="$(curl -sS -m 6 "http://127.0.0.1:\$PORT/openapi.json" | tr -d '\n' | grep -c '"/api/v1/deploy"' || true)"

echo "HAS_/api/deploy: \$([ "\$HAS_DEPLOY" -gt 0 ] && echo True || echo False)"
echo "HAS_/api/v1/deploy: \$([ "\$HAS_V1_DEPLOY" -gt 0 ] && echo True || echo False)"

echo "== local curl =="
curl -sS -m 6 "http://127.0.0.1:\$PORT/api/deploy" || true
echo ""
curl -sS -m 6 "http://127.0.0.1:\$PORT/api/v1/deploy" || true
echo ""

echo "== docker ps =="
docker ps --format '{{.Names}} {{.Image}}' | grep "\$NAME" || true

# exit non-zero if endpoints missing
if [ "\$HAS_DEPLOY" -eq 0 ] || [ "\$HAS_V1_DEPLOY" -eq 0 ]; then
  echo "❌ Missing deploy endpoints in OpenAPI"
  exit 20
fi

echo "✅ Internal proof OK"
BASH
done

log "External tests via AppGW/DNS"
EXT1="$(curl -sk -m 10 https://api.colconnect.fr/api/deploy  || true)"
EXT2="$(curl -sk -m 10 https://api.colconnect.fr/api/v1/deploy || true)"
echo "GET /api/deploy    => ${EXT1}"
echo "GET /api/v1/deploy => ${EXT2}"

PASS_EXTERNAL=1
echo "$EXT1" | grep -q '"deploy_sha"' || PASS_EXTERNAL=0
echo "$EXT2" | grep -q '"deploy_sha"' || PASS_EXTERNAL=0

log "RESULT"
if [ "$PASS_INTERNAL" -eq 1 ] && [ "$PASS_EXTERNAL" -eq 1 ]; then
  echo "✅✅✅ PASS: VMSS + AppGW serve /api/deploy and /api/v1/deploy in prod"
  echo "DEPLOY_SHA=$DEPLOY_SHA"
  exit 0
fi

echo "❌ FAIL:"
[ "$PASS_INTERNAL" -eq 0 ] && echo " - Internal proof failed on at least one VM"
[ "$PASS_EXTERNAL" -eq 0 ] && echo " - External AppGW test failed (routes not reachable)"
echo "DEPLOY_SHA=$DEPLOY_SHA"
exit 1

# ----------------------------------------------------------
# Git rollback (one step back) if needed:
#   git reset --hard HEAD~1
# ----------------------------------------------------------
