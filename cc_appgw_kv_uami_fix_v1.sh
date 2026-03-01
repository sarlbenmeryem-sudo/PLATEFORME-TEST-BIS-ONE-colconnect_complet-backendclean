#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV_NAME="kv-colconnect-prod-frc"

# UAMI (User Assigned Managed Identity)
UAMI_NAME="uami-appgw-kv-colconnect-prod-frc"

echo "== [1] Ensure UAMI =="
if az identity show -g "$RG" -n "$UAMI_NAME" >/dev/null 2>&1; then
  echo "✅ UAMI exists: $UAMI_NAME"
else
  az identity create -g "$RG" -n "$UAMI_NAME" -o none
  echo "✅ Created UAMI: $UAMI_NAME"
fi

UAMI_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query id -o tsv)"
UAMI_PRINCIPAL_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query principalId -o tsv)"
UAMI_CLIENT_ID="$(az identity show -g "$RG" -n "$UAMI_NAME" --query clientId -o tsv)"

echo "UAMI_ID=$UAMI_ID"
echo "UAMI_PRINCIPAL_ID=$UAMI_PRINCIPAL_ID"
echo "UAMI_CLIENT_ID=$UAMI_CLIENT_ID"

echo ""
echo "== [2] Attach UAMI to Application Gateway (top-level identity) =="
# IMPORTANT: AppGW requires UserAssigned identity for KeyVault secret-based SSL cert
az network application-gateway identity assign \
  -g "$RG" -n "$APPGW" \
  --identities "$UAMI_ID" -o none
echo "✅ Attached UAMI to AppGW"

echo ""
echo "== [3] Grant Key Vault access to UAMI =="
KV_ID="$(az keyvault show -g "$RG" -n "$KV_NAME" --query id -o tsv)"
RBAC_ENABLED="$(az keyvault show -g "$RG" -n "$KV_NAME" --query properties.enableRbacAuthorization -o tsv)"

echo "KV_ID=$KV_ID"
echo "enableRbacAuthorization=$RBAC_ENABLED"

if [[ "$RBAC_ENABLED" == "true" ]]; then
  echo "== KV is RBAC mode: assign RBAC role to UAMI =="
  # For AppGW to read cert secret, secrets "get" is required.
  # This built-in role is the typical minimum:
  # - "Key Vault Secrets User" => read secrets (get/list)
  az role assignment create \
    --assignee-object-id "$UAMI_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$KV_ID" -o none || true

  echo "✅ RBAC role assigned (or already existed)"
else
  echo "== KV is Access Policy mode: set access policy =="
  az keyvault set-policy \
    -g "$RG" -n "$KV_NAME" \
    --object-id "$UAMI_PRINCIPAL_ID" \
    --secret-permissions get list \
    -o none
  echo "✅ Access policy applied"
fi

echo ""
echo "== [4] Sanity check: show AppGW identity =="
az network application-gateway show -g "$RG" -n "$APPGW" --query "identity" -o json

echo ""
echo "✅ Done. Re-run your HTTPS enable script now."
