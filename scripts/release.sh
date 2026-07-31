#!/bin/bash
# Tag a release, build the zip, and publish it to GitHub with the notes from
# CHANGELOG.md. Usage: bash scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: bash scripts/release.sh X.Y.Z"; exit 1; }

command -v gh >/dev/null || { echo "gh not found. Run: brew install gh && gh auth login"; exit 1; }

BRANCH=$(git branch --show-current)   # works before the first commit too
[ "$BRANCH" = main ] || { echo "On branch $BRANCH — release from main."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree is dirty — commit the changelog first."; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "Tag v$VERSION already exists."; exit 1; }

# Notes = the body of this version's CHANGELOG section. No entry, no release.
NOTES=$(awk -v v="## [$VERSION]" '
    index($0, v) == 1 {found = 1; next}
    found && (/^## \[/ || /^\[[^]]+\]: /) {exit}   # next version, or the link-ref block
    found' CHANGELOG.md)
[ -n "${NOTES//[[:space:]]/}" ] || { echo "No '## [$VERSION] - YYYY-MM-DD' section with content in CHANGELOG.md."; exit 1; }

bash scripts/package.sh "$VERSION"

git tag -a "v$VERSION" -m "$VERSION"
git push origin main
git push origin "v$VERSION"

gh release create "v$VERSION" "dist/Wmj-Quick-Timer-$VERSION.zip" \
    --title "$VERSION" --notes "$NOTES"
