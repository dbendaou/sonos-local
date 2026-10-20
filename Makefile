.PHONY: test build app

# Swift 6 defaults to a macOS 12 target when the package does not say otherwise.
export MACOSX_DEPLOYMENT_TARGET := 14.0

test:
	@plugin=""; \
	devdir="$$(xcode-select -p 2>/dev/null || true)"; \
	if [ "$$(basename "$$devdir")" = "CommandLineTools" ]; then \
	  testdir="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"; \
	  if [ -d "$$testdir" ]; then plugin="$$testdir"; fi; \
	fi; \
	if [ -n "$$plugin" ]; then \
	  bash Scripts/with-sdk.sh swift test -Xswiftc -plugin-path -Xswiftc "$$plugin"; \
	else \
	  bash Scripts/with-sdk.sh swift test; \
	fi

build:
	bash Scripts/with-sdk.sh swift build --product SonosLocal

app:
	bash Scripts/build-app.sh
