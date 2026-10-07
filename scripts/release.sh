#!/usr/bin/env bash
set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is dirty. Commit or stash changes first."
    exit 1
fi

git fetch --tags origin >/dev/null 2>&1 || true

LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
BUMP="${1:-patch}"

if [[ -z "$LATEST_TAG" ]]; then
    if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        VERSION="$BUMP"
    else
        VERSION="0.1.0"
        echo "No previous tags found — using first release v$VERSION."
    fi
elif [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$BUMP"
else
    VERSION="${LATEST_TAG#v}"
    IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
    case "$BUMP" in
        major) VERSION="$((MAJOR + 1)).0.0" ;;
        minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
        patch) VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
        *) echo "Error: unknown bump type '$BUMP' (use patch, minor, major, or an explicit version like 1.2.3)." >&2; exit 1 ;;
    esac
fi

TAG="v$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists (latest is $LATEST_TAG)."
    exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git push origin "$CURRENT_BRANCH"
git tag "$TAG"
git push origin "$TAG"

echo "Pushed tag $TAG (previous: ${LATEST_TAG:-none}) — GitHub Actions will build and publish the release:"
echo "https://github.com/$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')/actions"
