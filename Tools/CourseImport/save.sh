#!/bin/sh
# Commits the given paths and pushes to main, for the Course import workflow.
# Usage: save.sh "commit message" path...
message="$1"
shift
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$@"
if git diff --cached --quiet; then
  echo "Nothing new"
  exit 0
fi
git commit -q -m "$message"
for i in 1 2 3; do
  git pull -q --rebase origin main && git push -q origin HEAD:main && exit 0
  sleep 5
done
exit 1
