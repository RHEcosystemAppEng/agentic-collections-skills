#!/usr/bin/env bash
# Validate only changed skills in CI (PRs and pushes to main).
# Exits 0 if no skills changed or all changed skills pass validation.
#
# Usage:
#   ./scripts/ci-validate-changed-skills.sh          # Run both Tier 1 + Tier 2
#   ./scripts/ci-validate-changed-skills.sh tier1     # Run only Tier 1 (agentskills.io)
#   ./scripts/ci-validate-changed-skills.sh tier2     # Run only Tier 2 (design principles)
#
# Local dev: set VALIDATE_INCLUDE_UNCOMMITTED=1 to include staged and unstaged changes.

set -e

TIER="${1:-all}"

if [ -n "$VALIDATE_INCLUDE_UNCOMMITTED" ]; then
  # Local dev: include staged + unstaged changes vs HEAD
  DIFF_CMD="git diff --name-only HEAD"
elif [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
  # Three-dot diff: merge-base(base, HEAD)..HEAD = changes in the PR
  BASE_REF="${GITHUB_BASE_REF:-main}"
  git fetch origin "$BASE_REF" 2>/dev/null || true
  DIFF_CMD="git diff --name-only origin/$BASE_REF...HEAD"
elif [ "$GITHUB_EVENT_NAME" = "push" ]; then
  # Push event: diff between before and after
  BEFORE="${GITHUB_EVENT_BEFORE:-}"
  if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
    echo "No base commit for diff, skipping skill validation"
    exit 0
  fi
  DIFF_CMD="git diff --name-only $BEFORE HEAD"
else
  # Default: local dev, include uncommitted changes
  DIFF_CMD="git diff --name-only HEAD"
fi

CHANGED=$($DIFF_CMD 2>/dev/null | grep -E '^[^/]+/skills/[^/]+/SKILL\.md$' | grep -v '^\.claude/' || true)

if [ -z "$CHANGED" ]; then
  echo "No skills changed, skipping skill validation"
  exit 0
fi

echo "Validating changed skills:"
echo "$CHANGED" | sed 's/^/  - /'

# Run validators on changed skills only
SKILL_ARGS=$(echo "$CHANGED" | tr '\n' ' ')

if [ "$TIER" = "tier1" ] || [ "$TIER" = "all" ]; then
  uv run python scripts/validate_skills_tier1.py $SKILL_ARGS
fi

if [ "$TIER" = "tier2" ] || [ "$TIER" = "all" ]; then
  uv run python scripts/validate_skills_tier2.py $SKILL_ARGS
  uv run python scripts/validate_skill_doc_links.py $SKILL_ARGS
  uv run python scripts/validate_docs_tree_links.py $SKILL_ARGS
fi
