#!/usr/bin/env bash
set -euo pipefail

repo_path="${1:-.}"
package_path="$(cd "$(dirname "$0")/.." && pwd)"
branch_name="${2:-fix/current-rpg-issues}"

cd "$repo_path"

git switch -c "$branch_name"
git add game content docs ISSUE_FIX_APPLY_RESULT.md
git commit -F "$package_path/COMMIT_MESSAGE.txt"
git push -u origin "$branch_name"

if command -v gh >/dev/null 2>&1; then
    gh pr create \
        --title "fix: resolve current Dota2 RPG gameplay and UI issues" \
        --body-file "$package_path/PR_BODY.md"
else
    printf '%s\n' "Branch pushed. GitHub CLI is not installed; create the PR with PR_BODY.md."
fi
