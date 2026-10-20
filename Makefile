.PHONY: test build app

# Swift 6 defaults to a macOS 12 target when the package does not say otherwise.
export MACOSX_DEPLOYMENT_TARGET := 14.0

test:
	bash Scripts/with-sdk.sh swift test

build:
	bash Scripts/with-sdk.sh swift build --product SonosLocal

app:
	bash Scripts/build-app.sh
