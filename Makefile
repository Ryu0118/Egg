SWIFTFORMAT := .nest/bin/swiftformat
SWIFTLINT := .nest/bin/swiftlint
MY_SWIFT_LINTER := .nest/bin/my-swift-linter

.PHONY: install-commands format lint my-lint format-lint hooks test e2e-test check

install-commands:
	mise install
	./scripts/nest.sh bootstrap nestfile.yaml

format:
	@test -f "$(SWIFTFORMAT)" || (echo "Run: make install-commands" && exit 1)
	"$(SWIFTFORMAT)" --config .swiftformat .

lint:
	@test -f "$(SWIFTLINT)" || (echo "Run: make install-commands" && exit 1)
	"$(SWIFTLINT)" lint --config .swiftlint.yml --strict --no-cache

my-lint:
	@test -f "$(MY_SWIFT_LINTER)" || (echo "Run: make install-commands" && exit 1)
	"$(MY_SWIFT_LINTER)"

format-lint: format lint

hooks:
	./scripts/setup-hooks.sh

test:
	swift test

e2e-test:
	cd E2ETestsPackage && swift test

check: format lint test e2e-test
