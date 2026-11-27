# Make targets are the interface. This package is iOS-only (UIKit/WebKit), so
# `swift test` on macOS can't build it: tests run through xcodebuild on an iOS
# simulator.
#
# DESTINATION defaults to the newest available iPhone simulator on this machine,
# so the same target works on the laptop and on omar without a hardcoded model.
# Override it to pin one: make test DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'

SCHEME ?= HotwireNative
SIM_ID ?= $(shell xcrun simctl list devices available | awk '/^-- iOS/{ios=1; next} /^-- /{ios=0} ios && /iPhone/ {match($$0, /\([0-9A-F-]{36}\)/); id=substr($$0, RSTART+1, RLENGTH-2)} END{print id}')
DESTINATION ?= platform=iOS Simulator,id=$(SIM_ID)
# xcbeautify if installed, plain output otherwise.
FORMATTER := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "| xcbeautify")

SHELL := /bin/bash
# GNU Make 3.81 (the version macOS ships, and the one CI runs) ignores
# .SHELLFLAGS, so the pipefail here is not enough on its own: each piped
# recipe also sets it inline. Without that, `xcodebuild ... | xcbeautify`
# exits with xcbeautify's status and a failing build or test looks green.
.SHELLFLAGS := -o pipefail -ec

.PHONY: help build test destination

help:
	@echo "make build        build the HotwireNative package for the iOS simulator"
	@echo "make test         run the package's unit tests on an iOS simulator"
	@echo "make destination  print the simulator destination that build/test will use"

destination:
	@echo "$(DESTINATION)"

build:
	set -o pipefail; xcodebuild build -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO $(FORMATTER)

test:
	set -o pipefail; xcodebuild test -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO $(FORMATTER)
