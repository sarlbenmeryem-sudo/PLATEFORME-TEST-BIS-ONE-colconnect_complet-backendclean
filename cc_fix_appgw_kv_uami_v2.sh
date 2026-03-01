#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV_NAME="kv-colconnect-prod-frc"
UAMI_NAME="uami-appgw-kv-colconnect-prod-frc"

echo "== [A] Ensure UAMI =="
if az identity show -g "$RG" -n "$UAMI_NAME" >/dev/null 2>&1; then
  echo "✅ UAMI exists: $UAMI_NAME"
else
  az identity create -g "$RG" -n "$UAMI_NAME" -o none
  echo "✅ Created UAMI: $UAMI_NAME"
fi

UAMI_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query id -o tsv)"
UAMI_PRINCIPAL_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query principalId -o tsv)"

echo "UAMI_ID=$UAMI_ID"
echo "UAMI_PRINCIPAL_ID=$UAMI_PRINCIPAL_ID"

echo ""
echo "== [B] Attach UAMI to AppGW (top-level identity) =="
az network application-gateway identity assign \
  -g "$RG" -n "$APPGW" \
  --identities "$UAMI_ID" -o none
echo "✅ Attached UAMI to AppGW"

echo ""
echo "== [C] Grant KV access to UAMI =="
KV_ID="$(az keyvault show -g "$RG" -n "$KV_NAME" --query id -o tsv)"
RBAC_ENABLED="$(az keyvault show -g "$RG" -n "$KV_NAME" --query properties.enableRbacAuthorization -o tsv)"
echo "enableRbacAuthorization=$RBAC_ENABLED"

if [[ "$RBAC_ENABLED" == "true" ]]; then
  echo "== KV RBAC mode: assign 'Key Vault Secrets User' to UAMI =="
  az role assignment create \
    --assignee-object-id "$UAMI_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$KV_ID" -o none || true
  echo "✅ RBAC role ok (created or already exists)"
else
  echo "== KV Access Policy mode: set secret get/list =="
  az keyvault set-policy \
    -g "$RG" -n "$KV_NAME" \
    --object-id "$UAMI_PRINCIPAL_ID" \
    --secret-permissions get list \
    -o none
  echo "✅ Access policy ok"
fi

echo ""
echo "== [D] Verify AppGW identity now =="
az network application-gateway show -g "$RG" -n "$APPGW" --query "identity" -o json

echo ""
echo "✅ DONE. Now re-run: ./cc_appgw_enable_https_from_pfx_v1.sh"
