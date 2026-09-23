APP_NAME := MiniClip
BUNDLE := build/$(APP_NAME).app
DEST := $(HOME)/Applications/$(APP_NAME).app
IDENTITY := MiniClip Dev

.PHONY: build test install

build:
	swift build -c release

test:
	swift test

install: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp .build/release/$(APP_NAME) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --sign "$(IDENTITY)" $(BUNDLE)
	-pkill -x $(APP_NAME)
	mkdir -p $(HOME)/Applications
	rm -rf "$(DEST)"
	cp -R $(BUNDLE) "$(DEST)"
	open "$(DEST)"
