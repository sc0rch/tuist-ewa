#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag>"
  echo "Example: $0 4.118.1-ewa.1"
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  echo "Error: mise is not installed."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh (GitHub CLI) is not installed."
  exit 1
fi

if ! command -v tuist >/dev/null 2>&1; then
  echo "Error: tuist is not installed (required by cli:bundle)."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean."
  exit 1
fi

ORIGIN_URL="$(git remote get-url origin)"
if [[ "$ORIGIN_URL" =~ github\.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
  GH_OWNER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]}"
else
  echo "Error: can't parse GitHub owner/repo from origin: $ORIGIN_URL"
  exit 1
fi

echo "Building artifacts (unsigned)..."
TUIST_EWA_SKIP_SIGNING=1 mise run cli:bundle

if [[ ! -f build/tuist.zip || ! -f build/SHASUMS256.txt ]]; then
  echo "Error: build outputs not found in ./build"
  exit 1
fi

SHA256="$(awk '/tuist\.zip/{print $1}' build/SHASUMS256.txt | head -n 1)"
if [[ -z "$SHA256" ]]; then
  echo "Error: sha256 for tuist.zip not found in build/SHASUMS256.txt"
  exit 1
fi

echo "Tagging and pushing: $TAG"
git tag "$TAG"
git push origin "$TAG"

echo "Creating GitHub release: $GH_OWNER/$GH_REPO $TAG"
gh release create "$TAG" \
  build/tuist.zip \
  build/ProjectDescription.xcframework.zip \
  build/SHASUMS256.txt \
  build/SHASUMS512.txt \
  --repo "$GH_OWNER/$GH_REPO" \
  --title "$TAG" \
  --notes ""

HOMEBREW_TOOLS_PATH="${HOMEBREW_TOOLS_PATH:-/Users/sc0rch/Documents/Develop/homebrew-tools}"
FORMULA_PATH="$HOMEBREW_TOOLS_PATH/Formula/tuist-ewa.rb"

if [[ ! -f "$FORMULA_PATH" ]]; then
  echo "Error: Homebrew formula not found at: $FORMULA_PATH"
  exit 1
fi

URL="https://github.com/$GH_OWNER/$GH_REPO/releases/download/$TAG/tuist.zip"

echo "Updating Homebrew formula: $FORMULA_PATH"
/usr/bin/ruby -pi -e "gsub(/homepage \".*\"/, 'homepage \"https://github.com/$GH_OWNER/$GH_REPO\"')" "$FORMULA_PATH"
/usr/bin/ruby -pi -e "gsub(/url \".*\"/, 'url \"$URL\"')" "$FORMULA_PATH"
/usr/bin/ruby -pi -e "gsub(/version \".*\"/, 'version \"$TAG\"')" "$FORMULA_PATH"
/usr/bin/ruby -pi -e "gsub(/sha256 \".*\"/, 'sha256 \"$SHA256\"')" "$FORMULA_PATH"

cd "$HOMEBREW_TOOLS_PATH"
git add "$FORMULA_PATH"
git commit -m "tuist-ewa $TAG"
git push

echo "Done."
echo "Formula url: $URL"
echo "Formula sha256: $SHA256"

