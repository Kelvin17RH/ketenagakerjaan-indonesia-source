#!/bin/bash
# update_netlify_split.sh
#
# Deploy the SPLIT-BUILD dashboard to the Netlify-watched GitHub repo.
# Bedanya dengan update_netlify.sh lama:
#   1. Push index.html (shell ~2.3 MB) bukan single-file 98 MB
#   2. Juga push _headers (Netlify cache policy untuk data/*.json)
#   3. Juga push folder data/ dengan 5 cube JSON files
#   4. Hapus file Indonesia_Labour_Dashboard.html lama di repo (kalau ada)
#
# Usage: deploy "commit message"
# (lewat alias 'deploy' di .zshrc yang baca $TOKEN dari Keychain)

set -e

# --- Config ---
REPO_USER="Kelvin17RH"
REPO_NAME="ketenagakerjaan-indonesia"
LOCAL_REPO="$HOME/Documents/$REPO_NAME"
SOURCE_DIR="$HOME/Documents/Claude/Projects/Indonesia Labour in Numbers"
COMMIT_MSG="${1:-Deploy split build}"

# --- Validate ---
if [ -z "$TOKEN" ]; then
  echo "ERROR: \$TOKEN not set. Run via the 'deploy' alias supaya Keychain dibaca." >&2
  exit 1
fi
if [ ! -f "$SOURCE_DIR/index.html" ]; then
  echo "ERROR: $SOURCE_DIR/index.html tidak ada. Run build_split.py dulu." >&2
  exit 1
fi
if [ ! -d "$SOURCE_DIR/data" ]; then
  echo "ERROR: $SOURCE_DIR/data folder tidak ada. Run build_split.py dulu." >&2
  exit 1
fi

# --- Clone or pull ---
if [ -d "$LOCAL_REPO/.git" ]; then
  echo "==> Pulling latest dari $REPO_NAME..."
  cd "$LOCAL_REPO"
  # Refresh token in remote URL so pull works
  git remote set-url origin "https://$TOKEN@github.com/$REPO_USER/$REPO_NAME.git"
  git pull origin main || echo "(pull failed, continuing — may be a non-fast-forward situation)"
else
  echo "==> Cloning $REPO_NAME..."
  git clone "https://$TOKEN@github.com/$REPO_USER/$REPO_NAME.git" "$LOCAL_REPO"
  cd "$LOCAL_REPO"
fi

# --- Copy fresh files ---
echo "==> Copying split-build files ke repo..."
cp "$SOURCE_DIR/index.html" "$LOCAL_REPO/index.html"
echo "    $(du -h "$SOURCE_DIR/index.html" | cut -f1)  → index.html"

if [ -f "$SOURCE_DIR/_headers" ]; then
  cp "$SOURCE_DIR/_headers" "$LOCAL_REPO/_headers"
  echo "    $(du -h "$SOURCE_DIR/_headers" | cut -f1)  → _headers"
fi

# Open Graph image for social-card previews (LinkedIn, Twitter, WhatsApp, etc.)
if [ -f "$SOURCE_DIR/og-image.png" ]; then
  cp "$SOURCE_DIR/og-image.png" "$LOCAL_REPO/og-image.png"
  echo "    $(du -h "$SOURCE_DIR/og-image.png" | cut -f1)  → og-image.png"
fi

mkdir -p "$LOCAL_REPO/data"
for f in "$SOURCE_DIR/data/"*.json; do
  if [ -f "$f" ]; then
    cp "$f" "$LOCAL_REPO/data/"
    echo "    $(du -h "$f" | cut -f1)  → data/$(basename "$f")"
  fi
done

# --- Remove stale single-file dashboard (kalau ada) ---
if [ -f "$LOCAL_REPO/Indonesia_Labour_Dashboard.html" ]; then
  echo "==> Removing stale Indonesia_Labour_Dashboard.html dari repo..."
  git rm "$LOCAL_REPO/Indonesia_Labour_Dashboard.html" 2>/dev/null || rm "$LOCAL_REPO/Indonesia_Labour_Dashboard.html"
fi

# --- Stage, commit, push ---
echo "==> Staging files..."
git add index.html
[ -f _headers ] && git add _headers
[ -f og-image.png ] && git add og-image.png
git add data/

echo "==> Committing: $COMMIT_MSG"
if git diff --cached --quiet; then
  echo "    Tidak ada perubahan (files sudah identik di repo)."
else
  git commit -m "$COMMIT_MSG"
fi

echo "==> Pushing ke GitHub..."
git remote set-url origin "https://$TOKEN@github.com/$REPO_USER/$REPO_NAME.git"
git push origin main

echo ""
echo "Deploy submitted."
echo "  Netlify akan auto-build dalam ~30 detik."
echo "  Live: https://ketenagakerjaan-indonesia.netlify.app"
