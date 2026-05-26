#!/bin/bash
# =============================================================================
# push-to-github.sh — one-shot setup to publish this workflow repo on GitHub
# =============================================================================
#
# What this does:
#   1. Verifies the current folder is a clean workflow-source/ tree.
#   2. Initialises a fresh git repo here (if not already).
#   3. Creates the GitHub repo via the GitHub API using your PAT.
#   4. Adds the remote, commits, and pushes 'main'.
#
# Prerequisites:
#   - Run from this folder (workflow-source/).
#   - The same Keychain PAT used by `deploy` works here (needs `repo` scope).
#   - `git`, `curl`, `jq` installed (jq optional but recommended for parse).
#
# Usage:
#     cd workflow-source
#     chmod +x push-to-github.sh
#     ./push-to-github.sh
#
# Override defaults via env vars:
#     REPO_NAME=my-custom-name REPO_PRIVATE=true ./push-to-github.sh

set -e

# --- Config (override via env if you want a different name) ---
REPO_USER="${REPO_USER:-Kelvin17RH}"
REPO_NAME="${REPO_NAME:-ketenagakerjaan-indonesia-source}"
REPO_DESC="${REPO_DESC:-Reproducible pipeline for the Sekilas Ketenagakerjaan Indonesia dashboard. Stata cleaning + Python aggregators + dashboard build scripts. Sakernas microdata not included.}"
REPO_PRIVATE="${REPO_PRIVATE:-false}"   # set 'true' for private
INITIAL_BRANCH="main"

# --- Read the PAT from Keychain (same one used by deploy) ---
if [ -z "$TOKEN" ]; then
  if command -v security >/dev/null 2>&1; then
    TOKEN=$(security find-generic-password -a "$USER" -s github_netlify_pat -w 2>/dev/null || true)
  fi
fi
if [ -z "$TOKEN" ]; then
  echo "✗ Could not read GitHub PAT from Keychain (service 'github_netlify_pat')."
  echo "  Either save it first:"
  echo "    security add-generic-password -a \$USER -s github_netlify_pat -w 'ghp_xxx'"
  echo "  Or export TOKEN before running this script: TOKEN=ghp_xxx ./push-to-github.sh"
  exit 1
fi

# --- Sanity: are we in the workflow-source folder? ---
if [ ! -f "README.md" ] || [ ! -d "01-stata-cleaning" ] || [ ! -d "02-python-aggregators" ] || [ ! -d "03-dashboard" ]; then
  echo "✗ This doesn't look like the workflow-source/ folder."
  echo "  Expected README.md + 01-stata-cleaning/ + 02-python-aggregators/ + 03-dashboard/."
  echo "  cd into the right folder and re-run."
  exit 1
fi

# --- Init git if needed ---
if [ ! -d ".git" ]; then
  echo "==> Initialising fresh git repo..."
  git init -q -b "$INITIAL_BRANCH"
else
  echo "==> Existing .git found — reusing."
  git checkout -q "$INITIAL_BRANCH" 2>/dev/null || git checkout -qb "$INITIAL_BRANCH"
fi

# --- Stage everything respecting .gitignore ---
git add -A
if git diff --cached --quiet; then
  echo "    Nothing to commit (working tree matches what's staged)."
else
  echo "==> Committing initial snapshot..."
  git commit -q -m "Initial workflow repo: Stata cleaning + Python aggregators + dashboard build pipeline" || true
fi

# --- Create the GitHub repo via API ---
echo "==> Checking whether $REPO_USER/$REPO_NAME already exists..."
HTTP_CODE=$(curl -s -o /tmp/gh_check.json -w "%{http_code}" \
  -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$REPO_USER/$REPO_NAME" || true)

if [ "$HTTP_CODE" = "404" ]; then
  echo "==> Repo not found — creating it on GitHub..."
  CREATE_PAYLOAD=$(cat <<EOF
{
  "name": "$REPO_NAME",
  "description": "$REPO_DESC",
  "private": $REPO_PRIVATE,
  "has_issues": true,
  "has_wiki": false,
  "auto_init": false
}
EOF
)
  CR_HTTP=$(curl -s -o /tmp/gh_create.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$CREATE_PAYLOAD" \
    https://api.github.com/user/repos)
  if [ "$CR_HTTP" != "201" ]; then
    echo "✗ Repo creation failed (HTTP $CR_HTTP):"
    cat /tmp/gh_create.json
    exit 2
  fi
  echo "    ✓ Created: https://github.com/$REPO_USER/$REPO_NAME"
elif [ "$HTTP_CODE" = "200" ]; then
  echo "    ✓ Repo already exists — will push to it."
else
  echo "✗ Unexpected response (HTTP $HTTP_CODE):"
  cat /tmp/gh_check.json
  exit 3
fi

# --- Configure remote + push ---
REMOTE_URL="https://$TOKEN@github.com/$REPO_USER/$REPO_NAME.git"
if git remote | grep -q '^origin$'; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

echo "==> Pushing $INITIAL_BRANCH to origin..."
git push -u origin "$INITIAL_BRANCH"

# --- Strip the token from the remote URL for tidiness (next pushes will use Keychain helper) ---
git remote set-url origin "https://github.com/$REPO_USER/$REPO_NAME.git"

echo ""
echo "✓ Done."
echo "  Live repo: https://github.com/$REPO_USER/$REPO_NAME"
echo ""
echo "  Next steps:"
echo "  - Edit the topics / About blurb on GitHub for discoverability."
echo "  - Optionally enable GitHub Pages for /docs."
echo "  - Future pushes: just \`git add -A && git commit -m 'msg' && git push\`."
