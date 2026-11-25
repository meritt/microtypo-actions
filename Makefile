SCRIPTS := install.sh uninstall.sh src/*.sh scripts/*.sh tests/*.sh

# Quick Actions run under the system bash 3.2, so tests do too.
BASH := /bin/bash

.PHONY: check test integration release

check:
	@for f in $(SCRIPTS); do bash -n "$$f"; done
	shellcheck $(SCRIPTS)

test:
	$(BASH) tests/test.sh

integration:
	$(BASH) tests/integration.sh

release:
	@[ -n "$(VERSION)" ] || { echo "usage: make release VERSION=v0.3.0"; exit 2; }
	scripts/build-release.sh "$(VERSION)" dist
