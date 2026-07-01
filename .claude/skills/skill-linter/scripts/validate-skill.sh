#!/bin/bash
# Thin wrapper — canonical validator is scripts/validate_skills_tier1.py
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
exec uv run python "$REPO_ROOT/scripts/validate_skills_tier1.py" "$@"
