#!/usr/bin/env bash
# Decides whether a fork PR is trusted enough to run secret-backed
# advisory workflows.
#
# Same-repo PRs are intentionally excluded here: they already run the
# normal pull_request e2e/e2e-ui workflows, so the trusted fork-only
# workflows should stay skipped to avoid duplicate signal.
#
# Env in: GH_TOKEN, REPO, PR, HEAD_REPO, MAINTAINERS
# Out:    allowed=true|false; reason=<human-readable>

set -euo pipefail

if [[ "$HEAD_REPO" == "$REPO" ]]; then
  echo "allowed=false" >> "$GITHUB_OUTPUT"
  echo "reason=same-repo PRs already run the standard e2e workflows" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [[ -z "${MAINTAINERS// /}" ]]; then
  echo "allowed=false" >> "$GITHUB_OUTPUT"
  echo "reason=no maintainers configured in .github/MAINTAINER on main" >> "$GITHUB_OUTPUT"
  exit 0
fi

MAINTAINERS_LC=$(echo "$MAINTAINERS" | tr '[:upper:]' '[:lower:]')

AUTHOR=$(gh pr view "$PR" --repo "$REPO" --json author --jq '.author.login')
AUTHOR_LC=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')
for m in $MAINTAINERS_LC; do
  if [[ "$m" == "$AUTHOR_LC" ]]; then
    echo "allowed=true" >> "$GITHUB_OUTPUT"
    echo "reason=author @$AUTHOR is a maintainer" >> "$GITHUB_OUTPUT"
    exit 0
  fi
done

APPROVERS=$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate \
  --jq '[.[] | select(.state != "COMMENTED")] | group_by(.user.login) | map(max_by(.submitted_at)) | .[] | select(.state == "APPROVED") | .user.login')

for u in $APPROVERS; do
  u_lc=$(echo "$u" | tr '[:upper:]' '[:lower:]')
  for m in $MAINTAINERS_LC; do
    if [[ "$m" == "$u_lc" ]]; then
      echo "allowed=true" >> "$GITHUB_OUTPUT"
      echo "reason=approved by maintainer @$u" >> "$GITHUB_OUTPUT"
      exit 0
    fi
  done
done

echo "allowed=false" >> "$GITHUB_OUTPUT"
echo "reason=fork PR has not been approved by a maintainer yet" >> "$GITHUB_OUTPUT"
