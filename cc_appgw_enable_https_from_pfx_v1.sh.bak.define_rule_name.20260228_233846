#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
RULE_PRIORITY="${RULE_PRIORITY:-100}"
RULE_NAME="${RULE_NAME:-rule-https-api-to-backend}"

PIP_RG="$RG"
PIP_NAME="pip-appgw-colconnect-prod"

# Domaine / cert
DOMAIN_FQDN="api.colconnect.fr"
PFX_WIN="C:\\Users\\benme\\Desktop\\api-colconnect-fr.pfx"
PFX_WSL="/mnt/c/Users/benme/Desktop/api-colconnect-fr.pfx"

# Key Vault (créé si absent)
KV_NAME="kv-colconnect-prod-frc"

# Noms AppGW
FEPORT_HTTPS="feport-https-443"
LISTENER_HTTPS="lst-https-api"
SSL_CERT_NAME="ssl-api-colconnect-fr"

PROBE_NAME="probe-api-health"
HTTPSETTINGS_NAME="bhs-api-8000"
RULE_REDIRECT_NAME="rule-redirect-http-to-https"
REDIRECT_CFG_NAME="redir-http-to-https"

# Routing (on garde le backend existant)
# Si tu as déjà un backend pool en place, on réutilise le premier.
BACKEND_POOL_ID="$(az network application-gateway address-pool list -g "$RG" --gateway-name "$APPGW" --query "[0].id" -o tsv)"
if [[ -z "${BACKEND_POOL_ID:-}" ]]; then
  echo "❌ Aucun backend pool trouvé sur l'AppGW. (On doit d'abord configurer le backend.)" >&2
  exit 1
fi

# Frontend IP config (on réutilise la première)
FEIP_ID="$(az network application-gateway frontend-ip list -g "$RG" --gateway-name "$APPGW" --query "[0].id" -o tsv)"
if [[ -z "${FEIP_ID:-}" ]]; then
  echo "❌ Aucune frontend IP config trouvée sur l'AppGW." >&2
  exit 1
fi

# Listener HTTP existant (port 80)
HTTP_LISTENER_ID="$(az network application-gateway http-listener list -g "$RG" --gateway-name "$APPGW" --query "[?protocol=='Http'] | [0].id" -o tsv)"
if [[ -z "${HTTP_LISTENER_ID:-}" ]]; then
  echo "❌ Aucun listener HTTP (80) trouvé sur l'AppGW." >&2
  exit 1
fi

echo "== Pre-checks =="
if [[ ! -f "$PFX_WSL" ]]; then
  echo "❌ PFX introuvable: $PFX_WSL" >&2
  echo "Windows path attendu: $PFX_WIN" >&2
  exit 1
fi
echo "✅ PFX OK: $PFX_WSL"
echo "BackendPool: $BACKEND_POOL_ID"
echo "FrontendIP:  $FEIP_ID"
echo "HttpListener:$HTTP_LISTENER_ID"

echo ""
echo "== Ensure Key Vault =="
if ! az keyvault show -g "$RG" -n "$KV_NAME" >/dev/null 2>&1; then
  az keyvault create -g "$RG" -n "$KV_NAME" -l "francecentral" >/dev/null
  echo "✅ KeyVault created: $KV_NAME"
else
  echo "✅ KeyVault exists: $KV_NAME"
fi

echo ""
echo "== Import PFX into Key Vault as cert =="
read -rsp "Enter PFX password (will not echo): " PFX_PASS
echo ""

# Nom du secret/cert dans KV
KV_CERT_NAME="${SSL_CERT_NAME}"

# Import (écrase si existe)
az keyvault certificate import \
  --vault-name "$KV_NAME" \
  -n "$KV_CERT_NAME" \
  -f "$PFX_WSL" \
  --password "$PFX_PASS" >/dev/null
echo "✅ Imported into KeyVault: $KV_NAME/$KV_CERT_NAME"

# Récupérer le secretId (versionné)
SECRET_ID="$(az keyvault certificate show --vault-name "$KV_NAME" -n "$KV_CERT_NAME" --query "sid" -o tsv)"
if [[ -z "${SECRET_ID:-}" ]]; then
  echo "❌ Impossible de récupérer sid (secretId) du cert KV." >&2
  exit 1
fi
echo "SecretId: $SECRET_ID"

echo ""
echo "== Ensure frontend port 443 =="
if ! az network application-gateway frontend-port show -g "$RG" --gateway-name "$APPGW" -n "$FEPORT_HTTPS" >/dev/null 2>&1; then
  az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" -n "$FEPORT_HTTPS" --port 443 >/dev/null
  echo "✅ Created frontend port 443: $FEPORT_HTTPS"
else
  echo "✅ Frontend port exists: $FEPORT_HTTPS"
fi
FEPORT_HTTPS_ID="$(az network application-gateway frontend-port show -g "$RG" --gateway-name "$APPGW" -n "$FEPORT_HTTPS" --query id -o tsv)"

echo ""
echo "== Ensure AppGW SSL cert object (from KeyVault) =="
if ! az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$SSL_CERT_NAME" >/dev/null 2>&1; then
  az network application-gateway ssl-cert create \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" >/dev/null
  echo "✅ Created AppGW ssl-cert: $SSL_CERT_NAME"
else
  # update to latest secretId if already exists
  az network application-gateway ssl-cert update \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" >/dev/null
  echo "✅ Updated AppGW ssl-cert: $SSL_CERT_NAME"
fi

echo ""
echo "== Ensure HTTPS listener 443 (host: $DOMAIN_FQDN) =="
if ! az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_HTTPS" >/dev/null 2>&1; then
  az network application-gateway http-listener create \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$LISTENER_HTTPS" \
    --frontend-ip "$FEIP_ID" \
    --frontend-port "$FEPORT_HTTPS_ID" \
    --ssl-cert "$SSL_CERT_NAME" \
    --host-name "$DOMAIN_FQDN" >/dev/null
  echo "✅ Created HTTPS listener: $LISTENER_HTTPS"
else
  echo "✅ HTTPS listener exists: $LISTENER_HTTPS"
fi
HTTPS_LISTENER_ID="$(az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_HTTPS" --query id -o tsv)"

echo ""
echo "== Ensure probe + http-settings (backend 8000) =="
if ! az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE_NAME" >/dev/null 2>&1; then
  az network application-gateway probe create \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$PROBE_NAME" \
    --protocol Http --path "/api/health" \
    --interval 30 --timeout 30 --threshold 3 \
    --pick-hostname-from-backend-http-settings false >/dev/null
  echo "✅ Created probe: $PROBE_NAME"
else
  echo "✅ Probe exists: $PROBE_NAME"
fi

if ! az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$HTTPSETTINGS_NAME" >/dev/null 2>&1; then
  az network application-gateway http-settings create \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$HTTPSETTINGS_NAME" \
    --port 8000 --protocol Http \
    --timeout 30 \
    --probe "$PROBE_NAME" \
    --cookie-based-affinity Disabled >/dev/null
  echo "✅ Created backend http-settings: $HTTPSETTINGS_NAME"
else
  echo "✅ Backend http-settings exists: $HTTPSETTINGS_NAME"
fi
HTTPSETTINGS_ID="$(az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$HTTPSETTINGS_NAME" --query id -o tsv)"

echo ""
echo "== Ensure routing rule for HTTPS listener -> backend =="

echo ""
echo "== Ensure routing rule priority (required by API >= 2021-08-01) =="
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_NAME" >/dev/null 2>&1; then
  echo "ℹ️ Rule exists: $RULE_NAME -> set priority=$RULE_PRIORITY"
  az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_NAME" --priority "$RULE_PRIORITY" >/dev/null
fi
RULE_HTTPS_NAME="rule-https-api-to-backend"
if ! az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_NAME" >/dev/null 2>&1; then
  az network application-gateway rule create \
    --priority "$RULE_PRIORITY" \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$RULE_HTTPS_NAME" \
    --rule-type Basic \
    --http-listener "$HTTPS_LISTENER_ID" \
    --address-pool "$BACKEND_POOL_ID" \
    --http-settings "$HTTPSETTINGS_ID" >/dev/null
  echo "✅ Created rule: $RULE_HTTPS_NAME"
else
  echo "✅ Rule exists: $RULE_HTTPS_NAME"
fi

echo ""
echo "== Ensure redirect HTTP->HTTPS =="
if ! az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIRECT_CFG_NAME" >/dev/null 2>&1; then
  az network application-gateway redirect-config create \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$REDIRECT_CFG_NAME" \
    --type Permanent \
    --target-listener "$HTTPS_LISTENER_ID" \
    --include-path true --include-query-string true >/dev/null
  echo "✅ Created redirect-config: $REDIRECT_CFG_NAME"
else
  echo "✅ Redirect-config exists: $REDIRECT_CFG_NAME"
fi

# Mettre à jour la rule HTTP existante pour rediriger
HTTP_RULE_ID="$(az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" --query "[?httpListener.id=='$HTTP_LISTENER_ID'] | [0].id" -o tsv)"
if [[ -z "${HTTP_RULE_ID:-}" ]]; then
  echo "⚠️ Aucune rule HTTP trouvée attachée au listener 80. On en crée une de redirection."
  az network application-gateway rule create \
    --priority "$RULE_PRIORITY" \
    -g "$RG" --gateway-name "$APPGW" \
    -n "$RULE_REDIRECT_NAME" \
    --rule-type Basic \
    --http-listener "$HTTP_LISTENER_ID" \
    --redirect-config "$REDIRECT_CFG_NAME" >/dev/null
  echo "✅ Created redirect rule: $RULE_REDIRECT_NAME"
else
  az network application-gateway rule update \
    --ids "$HTTP_RULE_ID" \
    --redirect-config "$REDIRECT_CFG_NAME" >/dev/null
  echo "✅ Updated existing HTTP rule to redirect -> HTTPS"
fi

echo ""
echo "== Optional: set DNS label on Public IP (creates *.cloudapp.azure.com FQDN) =="
DNS_LABEL="cc-api-prod-frc"
az network public-ip update -g "$PIP_RG" -n "$PIP_NAME" --dns-name "$DNS_LABEL" >/dev/null
FQDN="$(az network public-ip show -g "$PIP_RG" -n "$PIP_NAME" --query "dnsSettings.fqdn" -o tsv)"
echo "✅ Public IP FQDN: $FQDN"

echo ""
echo "== Final checks =="
echo "Test HTTPS (should be 200):"
echo "  curl -I https://$DOMAIN_FQDN/api/health"
echo "Test redirect (should be 301/308):"
echo "  curl -I http://$DOMAIN_FQDN/api/health"
echo ""
echo "Rollback (git): git reset --hard HEAD~1"
