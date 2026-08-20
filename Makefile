APP_NAME := ConsoleMode
BUNDLE := $(APP_NAME).app
BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/$(APP_NAME)

.PHONY: build bundle run test clean

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(BUNDLE)"

run: bundle
	open "$(BUNDLE)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(BUNDLE)"
