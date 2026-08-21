APP_NAME := ConsoleMode
BUNDLE := $(APP_NAME).app
BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/$(APP_NAME)

.PHONY: build bundle run test snapshots clean

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

# Headless render of the real panel views to /tmp/console-mode-snapshots.
# Needs no Screen Recording or Accessibility permission and never shows a window.
snapshots:
	swift test --filter PanelHarnessTests
	@echo
	@ls -1 /tmp/console-mode-snapshots/*.png

clean:
	swift package clean
	rm -rf "$(BUNDLE)"
