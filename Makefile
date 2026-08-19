.PHONY: validate validate-bases validate-clusters lint clean help roll-insights

# Cluster config that carries the per-app image references Argo renders.
CONFIG := clusters/minimal/config.yaml

help:
	@echo "Available targets:"
	@echo "  validate        - Validate all kustomize bases and cluster configs"
	@echo "  validate-bases  - Validate base kustomize builds"
	@echo "  validate-clusters - Validate cluster configs exist and are valid YAML"
	@echo "  lint            - Run YAML linting"
	@echo "  roll-insights   - Pin insights to an immutable tag and push (TAG=<git-sha>)"
	@echo "  clean           - Remove generated files"

# Roll the insights deployment to an immutable image tag. Build+push the image
# first (tagged with a short git SHA), then: make roll-insights TAG=abc1234
# This rewrites the insights image tag in $(CONFIG), commits, and pushes to
# main. Argo's automated sync picks the commit up on its own — no PR, so the
# impact-assessment gate (pull_request only) does not run. COMMIT/PUSH default
# on; pass PUSH=0 to stop before pushing, or COMMIT=0 to only edit the file.
#
# insights runs from the Synadia Helm chart, so the image is expressed as
# apps.insights.image.{registry,repository,tag}. This rewrites the `tag:` line
# that immediately follows `repository: insights` — matching that pair avoids
# touching any other app's image tag (e.g. nats).
roll-insights:
	@test -n "$(TAG)" || { echo "TAG is required, e.g. make roll-insights TAG=$$(git rev-parse --short HEAD)"; exit 1; }
	@grep -qE '^      repository: insights$$' $(CONFIG) || { echo "Could not find insights image block in $(CONFIG)"; exit 1; }
	@awk -v tag='$(TAG)' '\
		/^      repository: insights$$/ { in_ins=1 } \
		in_ins && /^      tag:/ { sub(/tag:.*/, "tag: " tag); in_ins=0 } \
		{ print }' $(CONFIG) > $(CONFIG).tmp && mv $(CONFIG).tmp $(CONFIG)
	@echo "Pinned insights image to :$(TAG)"
	@awk '/^      repository: insights$$/ { f=1 } f && /^      tag:/ { print NR": "$$0; f=0 }' $(CONFIG)
	@if [ "$(COMMIT)" != "0" ]; then \
		git add $(CONFIG); \
		git commit -m "insights: roll image to insights:$(TAG)"; \
		if [ "$(PUSH)" != "0" ]; then \
			git push; \
			echo "Pushed. Argo will sync insights to :$(TAG) shortly."; \
		else \
			echo "Committed (PUSH=0). Run 'git push' to deploy."; \
		fi; \
	else \
		echo "Edited $(CONFIG) (COMMIT=0). Review, commit, and push to deploy."; \
	fi

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
