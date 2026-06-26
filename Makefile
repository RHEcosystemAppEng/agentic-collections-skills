.PHONY: help install validate validate-collection-schema validate-collection-compliance validate-skill-design validate-skill-design-changed validate-mcp-tools clean check-uv

help:
	@echo "agentic-collections-skills"
	@echo ""
	@echo "Available targets:"
	@echo "  install                       - Install Python dependencies (requires uv)"
	@echo "  validate                      - Pack structure + skill doc links + collection compliance + MCP tools"
	@echo "  validate-collection-schema    - Schema + roster + banners (subset of compliance)"
	@echo "  validate-collection-compliance - Full .catalog compliance (includes collection.json drift)"
	@echo "  validate-skill-design         - Validate all skills (use PACK=rh-sre for a specific pack)"
	@echo "  validate-skill-design-changed - Validate only changed skills (staged + unstaged, for local dev)"
	@echo "  validate-mcp-tools            - Validate allowed-tools against live MCP servers (requires podman)"
	@echo "  clean                         - Remove generated files"
	@echo ""
	@echo "Requirements:"
	@echo "  uv - Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"

check-uv:
	@command -v uv >/dev/null 2>&1 || { \
		echo "Error: uv is not installed"; \
		echo ""; \
		echo "Install uv with:"; \
		echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"; \
		echo ""; \
		echo "Or visit: https://github.com/astral-sh/uv"; \
		exit 1; \
	}

install: check-uv
	@echo "Installing Python dependencies with uv..."
	@uv sync --group dev
	@echo "Dependencies installed in isolated environment (includes dev: pre-commit for git hooks)!"

validate: check-uv
	@echo "Validating agentic collection structure..."
	@uv run python scripts/validate_structure.py
	@echo "Validating skill docs links..."
	@uv run python scripts/validate_skill_doc_links.py
	@echo "Validating docs tree links..."
	@uv run python scripts/validate_docs_tree_links.py
	@echo "Validating collection compliance (.catalog/)..."
	@uv run python scripts/validate_collection_compliance.py
	@echo "Validating MCP tool references (skips gracefully without podman)..."
	@uv run python scripts/validate_mcp_tools.py --summary-only --log-file .validate/mcp-tools.log
	@echo "Validation complete!"

validate-collection-schema: check-uv
	@uv run python scripts/validate_collection_schema.py

validate-collection-compliance: check-uv
	@uv run python scripts/validate_collection_compliance.py

validate-skill-design: check-uv
	@uv run python scripts/validate_skill_design.py $(if $(PACK),$(PACK))

validate-skill-design-changed: check-uv
	@VALIDATE_INCLUDE_UNCOMMITTED=1 ./scripts/ci-validate-changed-skills.sh

validate-mcp-tools: check-uv
	@echo "Validating MCP tool references against live servers..."
	@uv run python scripts/validate_mcp_tools.py $(if $(PACK),$(PACK))
	@echo "MCP tool validation complete!"

clean:
	@echo "Cleaning generated files..."
	@rm -rf .validate/
	@echo "Cleaned!"
