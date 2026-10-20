.PHONY: test build app

test:
	swift test

build:
	swift build --product SonosLocal

app:
	Scripts/build-app.sh
