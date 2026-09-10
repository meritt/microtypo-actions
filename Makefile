SCRIPTS := install.sh uninstall.sh src/*.sh scripts/*.sh tests/*.sh

.PHONY: check test integration release

check:
	@for f in $(SCRIPTS); do bash -n "$$f"; done
	shellcheck $(SCRIPTS)

test:
	bash tests/test.sh

integration:
	bash tests/integration.sh

release:
	@[ -n "$(VERSION)" ] || { echo "usage: make release VERSION=v0.1.0"; exit 2; }
	scripts/build-release.sh "$(VERSION)" dist
