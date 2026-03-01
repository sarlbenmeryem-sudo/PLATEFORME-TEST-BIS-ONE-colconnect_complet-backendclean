#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="./colconnect_vitrine"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need git

if [[ ! -d "$REPO_DIR" ]]; then
  echo "❌ Missing $REPO_DIR. Run generator patch first." >&2
  exit 1
fi

cd "$REPO_DIR"

if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi

git add .
git commit -m "vitrine: initial institutional site (SEO+headers+canonical+RGPD+API page)" || true

echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
