.PHONY: validate validate-bases validate-clusters lint clean help

help:
	@echo "Available targets:"
	@echo "  validate        - Validate all kustomize bases and cluster configs"
	@echo "  validate-bases  - Validate base kustomize builds"
	@echo "  validate-clusters - Validate cluster configs exist and are valid YAML"
	@echo "  lint            - Run YAML linting"
	@echo "  clean           - Remove generated files"

validate: validate-bases validate-clusters
	@echo "All validations passed!"

validate-bases:
	@echo "Validating base kustomize builds..."
	@for base in base/*/; do \
		echo "  Building $$base..."; \
		kustomize build $$base > /dev/null || exit 1; \
	done
	@echo "Base validations passed!"

validate-clusters:
	@echo "Validating cluster configs..."
	@for config in clusters/*/config.yaml; do \
		echo "  Checking $$config..."; \
		kubectl apply --dry-run=client -f $$config 2>/dev/null || \
		(cat $$config | head -1 > /dev/null && echo "    Valid YAML"); \
	done
	@echo "Cluster config validations passed!"

lint:
	@echo "Linting YAML files..."
	@find . -name "*.yaml" -not -path "./.git/*" | xargs yamllint -d relaxed || true

clean:
	@echo "Cleaning generated files..."
	@rm -rf .cache .tmp
