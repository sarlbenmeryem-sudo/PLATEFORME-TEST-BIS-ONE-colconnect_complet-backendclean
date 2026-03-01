#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV_NAME="kv-colconnect-prod-frc"
UAMI_NAME="uami-appgw-kv-colconnect-prod-frc"

TARGET_SCRIPT="./cc_appgw_enable_https_from_pfx_v1.sh"

echo "== [CC_PATCH_APPGW_KV_UAMI_AND_RETRY_V2] Start =="

if [[ ! -f "$TARGET_SCRIPT" ]]; then
  echo "❌ Target script not found: $TARGET_SCRIPT" >&2
  exit 1
fi
chmod +x "$TARGET_SCRIPT" || true

echo ""
echo "== [1] Ensure User Assigned Managed Identity (UAMI) =="
if az identity show -g "$RG" -n "$UAMI_NAME" >/dev/null 2>&1; then
  echo "✅ UAMI exists: $UAMI_NAME"
else
  az identity create -g "$RG" -n "$UAMI_NAME" -o none
  echo "✅ Created UAMI: $UAMI_NAME"
fi

UAMI_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query id -o tsv)"
UAMI_PRINCIPAL_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query principalId -o tsv)"

if [[ -z "${UAMI_ID:-}" || -z "${UAMI_PRINCIPAL_ID:-}" ]]; then
  echo "❌ Failed to resolve UAMI_ID or UAMI_PRINCIPAL_ID" >&2
  exit 1
fi

echo "UAMI_ID=$UAMI_ID"
echo "UAMI_PRINCIPAL_ID=$UAMI_PRINCIPAL_ID"

echo ""
echo "== [2] Attach UAMI to Application Gateway (top-level identity) =="
# Correct CLI params: --gateway-name + --identity
az network application-gateway identity assign \
  -g "$RG" \
  --gateway-name "$APPGW" \
  --identity "$UAMI_ID" \
  -o none
echo "✅ Attached UAMI to AppGW: $APPGW"

echo ""
echo "== [3] Grant Key Vault secret GET/LIST to UAMI (RBAC or Access Policy) =="
KV_ID="$(az keyvault show -g "$RG" -n "$KV_NAME" --query id -o tsv)"
RBAC_ENABLED="$(az keyvault show -g "$RG" -n "$KV_NAME" --query properties.enableRbacAuthorization -o tsv)"

if [[ -z "${KV_ID:-}" ]]; then
  echo "❌ Failed to resolve KV_ID for $KV_NAME" >&2
  exit 1
fi

echo "KV_ID=$KV_ID"
echo "enableRbacAuthorization=$RBAC_ENABLED"

if [[ "$RBAC_ENABLED" == "true" ]]; then
  echo "== KV in RBAC mode: assign 'Key Vault Secrets User' to UAMI =="
  az role assignment create \
    --assignee-object-id "$UAMI_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$KV_ID" -o none || true
  echo "✅ RBAC role ensured"
else
  echo "== KV in Access Policy mode: set secret permissions get/list =="
  az keyvault set-policy \
    -g "$RG" -n "$KV_NAME" \
    --object-id "$UAMI_PRINCIPAL_ID" \
    --secret-permissions get list \
    -o none
  echo "✅ Access policy ensured"
fi

echo ""
echo "== [4] Verify AppGW identity now =="
az network application-gateway show -g "$RG" -n "$APPGW" --query "identity" -o json

echo ""
echo "== [5] Re-run HTTPS enable script (2 attempts) =="
set +e
"$TARGET_SCRIPT"
RC1=$?
set -e

if [[ $RC1 -ne 0 ]]; then
  echo ""
  echo "⚠️ First retry failed (often RBAC propagation). Waiting 120s then retrying once..."
  sleep 120
  "$TARGET_SCRIPT"
fi

echo ""
echo "== [CC_PATCH_APPGW_KV_UAMI_AND_RETRY_V2] Done =="
