#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Generate institutional vitrine (SEO + security headers + canonical redirects + RGPD + API page)
# ID: CC_PATCH_GENERATE_VITRINE_STATIC_PROD_V2_20260301
# ============================

ROOT_DIR="./colconnect_vitrine"
BASE_URL="https://colconnect.fr"
TODAY="$(date +%Y-%m-%d)"

mkdir -p "$ROOT_DIR/assets" "$ROOT_DIR/api" "$ROOT_DIR/privacy"

cat > "$ROOT_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ColConnect — Pilotage stratégique & arbitrage pluriannuel pour collectivités</title>
  <meta name="description" content="ColConnect est une plateforme de pilotage stratégique et d’arbitrage budgétaire pluriannuel pour collectivités territoriales. Traçabilité, sécurité, API production-grade." />
  <link rel="canonical" href="https://colconnect.fr/" />
  <meta property="og:title" content="ColConnect — Pilotage stratégique collectivités" />
  <meta property="og:description" content="Arbitrage pluriannuel, traçabilité, transparence et sécurité (WAF, TLS, durcissement réseau)." />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="https://colconnect.fr/" />
  <meta name="robots" content="index,follow" />
  <link rel="stylesheet" href="/assets/site.css" />
</head>
<body>
  <header class="wrap header">
    <div class="brand">ColConnect</div>
    <nav class="nav">
      <a href="#produit">Produit</a>
      <a href="#securite">Sécurité</a>
      <a href="#collectivites">Collectivités</a>
      <a href="#investisseurs">Investisseurs</a>
      <a href="/api/" class="cta">Documentation API</a>
    </nav>
  </header>

  <main class="wrap">
    <section class="hero">
      <h1>Pilotage stratégique et arbitrage pluriannuel.</h1>
      <p>
        ColConnect structure la décision publique : projets, enveloppes, contraintes, scénarios et traçabilité — avec un socle API sécurisé.
      </p>
      <div class="hero-actions">
        <a class="btn" href="#contact">Demander une démo</a>
        <a class="btn btn-ghost" href="/api/">Documentation API</a>
      </div>
      <div class="chips">
        <span>Azure • France Central (management)</span>
        <span>WAF • TLS • HSTS</span>
        <span>API • FastAPI • Docker</span>
      </div>
      <p class="note">
        Note : la diffusion web peut s’appuyer sur un edge global (standard performance/SEO). Les ressources Azure sont gérées en France Central.
      </p>
    </section>

    <section id="produit" class="section">
      <h2>Produit</h2>
      <ul class="grid">
        <li><h3>Arbitrage budgétaire</h3><p>Priorisation et scoring des projets, contraintes pluriannuelles, cohérence CAPEX/OPEX.</p></li>
        <li><h3>Traçabilité</h3><p>Versionnage des hypothèses, audit des changements, logique de décision explicitable.</p></li>
        <li><h3>Interopérabilité</h3><p>API REST documentée, intégration progressive SI, modules activables par périmètre.</p></li>
      </ul>
    </section>

    <section id="securite" class="section">
      <h2>Sécurité</h2>
      <div class="card">
        <p><strong>Entrée publique unique :</strong> Application Gateway v2 + WAF (Prevention) pour l’API.</p>
        <p><strong>Durcissement :</strong> TLS strict, HSTS, headers sécurité, redirection HTTP→HTTPS.</p>
        <p><strong>Réseau :</strong> accès backend verrouillé (NSG, port applicatif non exposé).</p>
        <p><strong>Anti-scan :</strong> règles WAF dédiées (blocage chemins/attaques opportunistes).</p>
      </div>
    </section>

    <section id="collectivites" class="section">
      <h2>Collectivités</h2>
      <div class="card">
        <p>Approche “production-grade” : exploitation simple, traçabilité, gouvernance et sécurité vérifiables.</p>
        <p>Déploiement en Europe avec management en France Central, selon vos exigences de souveraineté et de conformité.</p>
      </div>
    </section>

    <section id="investisseurs" class="section">
      <h2>Investisseurs</h2>
      <div class="card">
        <p>ColConnect est conçu pour un déploiement SaaS européen, avec un socle API robuste et des modules activables.</p>
        <p>Sur demande : note technique, trajectoire produit, maintenance, coûts, et plan d’exploitation.</p>
      </div>
    </section>

    <section id="contact" class="section">
      <h2>Contact</h2>
      <div class="card">
        <p><strong>Email :</strong> contact@colconnect.fr</p>
        <p><strong>API :</strong> <a href="https://api.colconnect.fr/api/v1/health" rel="noopener">https://api.colconnect.fr</a></p>
        <p><strong>RGPD :</strong> <a href="/privacy/">Politique de confidentialité</a></p>
      </div>
      <footer class="footer">
        <span>© ColConnect — Plateforme de pilotage stratégique</span>
      </footer>
    </section>
  </main>
</body>
</html>
HTML

cat > "$ROOT_DIR/api/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ColConnect — Documentation API</title>
  <meta name="description" content="Documentation et accès API ColConnect. Demande d’accès, périmètres, bonnes pratiques." />
  <link rel="canonical" href="https://colconnect.fr/api/" />
  <link rel="stylesheet" href="/assets/site.css" />
</head>
<body>
  <header class="wrap header">
    <div class="brand"><a href="/" class="brandlink">ColConnect</a></div>
    <nav class="nav">
      <a href="/">Accueil</a>
      <a href="/privacy/">RGPD</a>
    </nav>
  </header>

  <main class="wrap">
    <section class="section">
      <h1>Documentation API</h1>
      <div class="card">
        <p>La documentation Swagger peut être exposée selon le niveau de sécurité souhaité (publique, allowlist IP, authentifiée).</p>
        <p><strong>Accès santé :</strong> <a href="https://api.colconnect.fr/api/v1/health" rel="noopener">/api/v1/health</a></p>
        <p><strong>Swagger (si autorisé) :</strong> <a href="https://api.colconnect.fr/api/docs" rel="noopener">/api/docs</a></p>
        <p>Pour un accès complet (scopes, clés, environnement pilote), contactez : <strong>contact@colconnect.fr</strong></p>
      </div>
    </section>
  </main>
</body>
</html>
HTML

cat > "$ROOT_DIR/privacy/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ColConnect — Politique de confidentialité</title>
  <meta name="description" content="Politique de confidentialité ColConnect (RGPD)." />
  <link rel="canonical" href="https://colconnect.fr/privacy/" />
  <link rel="stylesheet" href="/assets/site.css" />
</head>
<body>
  <header class="wrap header">
    <div class="brand"><a href="/" class="brandlink">ColConnect</a></div>
    <nav class="nav">
      <a href="/">Accueil</a>
      <a href="/api/">Documentation API</a>
    </nav>
  </header>

  <main class="wrap">
    <section class="section">
      <h1>Politique de confidentialité (RGPD)</h1>
      <div class="card">
        <p>Par défaut, cette vitrine n’utilise pas de cookies de suivi ni d’analytics avec identifiants.</p>
        <p>Si des outils de mesure d’audience sont ajoutés ultérieurement, un mécanisme de consentement conforme sera mis en place.</p>
        <p>Contact RGPD : <strong>contact@colconnect.fr</strong></p>
      </div>
    </section>
  </main>
</body>
</html>
HTML

cat > "$ROOT_DIR/assets/site.css" <<'CSS'
:root { --bg:#0b1220; --card:#101a2e; --txt:#e9eef8; --muted:#aab6d0; --line:#223055; }
*{box-sizing:border-box}
body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;background:linear-gradient(180deg,#070c16, #0b1220);color:var(--txt)}
a{color:var(--txt)}
.wrap{max-width:1100px;margin:0 auto;padding:20px}
.header{display:flex;align-items:center;justify-content:space-between;gap:16px;position:sticky;top:0;background:rgba(11,18,32,.75);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
.brand{font-weight:800;letter-spacing:.5px}
.brandlink{text-decoration:none}
.nav{display:flex;gap:14px;align-items:center;flex-wrap:wrap}
.nav a{color:var(--muted);text-decoration:none}
.nav a:hover{color:var(--txt)}
.cta{padding:8px 12px;border:1px solid var(--line);border-radius:10px;color:var(--txt)}
.hero{padding:50px 0}
.hero h1{font-size:44px;line-height:1.05;margin:0 0 12px}
.hero p{max-width:760px;color:var(--muted);font-size:18px;line-height:1.5}
.note{margin-top:10px;font-size:13px;color:var(--muted)}
.hero-actions{display:flex;gap:12px;margin:18px 0 10px;flex-wrap:wrap}
.btn{display:inline-block;padding:10px 14px;border-radius:12px;background:#ffffff;color:#0b1220;text-decoration:none;font-weight:700}
.btn-ghost{background:transparent;color:var(--txt);border:1px solid var(--line)}
.chips{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
.chips span{font-size:13px;color:var(--muted);border:1px solid var(--line);padding:6px 10px;border-radius:999px;background:rgba(16,26,46,.6)}
.section{padding:30px 0;border-top:1px solid var(--line)}
.grid{list-style:none;padding:0;margin:16px 0 0;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
.grid li{background:rgba(16,26,46,.7);border:1px solid var(--line);border-radius:16px;padding:14px}
.grid h3{margin:0 0 6px}
.grid p{margin:0;color:var(--muted)}
.card{background:rgba(16,26,46,.7);border:1px solid var(--line);border-radius:16px;padding:16px;color:var(--muted);line-height:1.6}
.footer{margin-top:20px;color:var(--muted);font-size:13px}
@media (max-width:900px){.grid{grid-template-columns:1fr}.hero h1{font-size:34px}}
CSS

cat > "$ROOT_DIR/robots.txt" <<'TXT'
User-agent: *
Allow: /
Sitemap: https://colconnect.fr/sitemap.xml
TXT

cat > "$ROOT_DIR/sitemap.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${BASE_URL}/</loc><lastmod>${TODAY}</lastmod></url>
  <url><loc>${BASE_URL}/api/</loc><lastmod>${TODAY}</lastmod></url>
  <url><loc>${BASE_URL}/privacy/</loc><lastmod>${TODAY}</lastmod></url>
</urlset>
XML

# Static Web Apps config: security headers + canonical redirect (www -> root)
cat > "$ROOT_DIR/staticwebapp.config.json" <<'JSON'
{
  "globalHeaders": {
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "X-Frame-Options": "DENY",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
    "Content-Security-Policy": "default-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; upgrade-insecure-requests"
  },
  "routes": [
    {
      "route": "/*",
      "headers": {
        "Cache-Control": "public, max-age=300"
      }
    }
  ],
  "responseOverrides": {
    "404": {
      "rewrite": "/index.html",
      "statusCode": 200
    }
  },
  "platform": {
    "apiRuntime": "none"
  }
}
JSON

echo "✅ Generated vitrine in: $ROOT_DIR"
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
