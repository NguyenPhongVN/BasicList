#!/bin/bash
# run-all-tests.sh — the FULL local test pass, CI mirrored in one command.
#
# `swift test` alone runs only the macOS-host suites (43 wiring/semantics
# tests) — green there says NOTHING about render/interaction/load-more
# timing, which lives in the two iOS-only simulator suites (`#if os(iOS)`).
# This script runs the whole truth, in the same order and isolation CI does:
#   1. host suites — `swift test` on the macOS host (CI runs the same tests
#      on the simulator because the CI host OS is older than .macOS(.v26);
#      locally the host is faster and the suites are platform-agnostic)
#   2. LoadMoreSimulatorTests — xcodebuild, SEPARATE invocation
#   3. InteractionSimulatorTests — xcodebuild, SEPARATE invocation
#
# Why 2 and 3 are separate: both suites are @MainActor with blocking
# RunLoop pumps, and swift-testing serializes WITHIN each suite only — one
# invocation interleaves their measurement windows and perturbs the
# load-more timing assertions (CI run #11).
#
# The interaction suite inspects the a11y tree, which SwiftUI only
# materializes when accessibility is enabled: on iOS 26.5+ the harness
# notifications alone suffice, older runtimes (≤26.2) need the
# accessibility defaults — written here before the test run boots the
# simulator (same step as CI).
#
# Usage:
#   Scripts/run-all-tests.sh                     # auto-pick an available iPhone
#   Scripts/run-all-tests.sh "iPhone 17 Pro Test"
#   SIMULATOR_NAME="iPhone 17 Pro Test" Scripts/run-all-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Pick the simulator: arg 1 > env > CI's preferred name > first available
PREFERRED="iPhone 18 Pro Max"
NAME="${1:-${SIMULATOR_NAME:-}}"
if [ -z "$NAME" ]; then
    if xcrun simctl list devices available | grep -q "$PREFERRED ("; then
        NAME="$PREFERRED"
    else
        # NOT `awk -F ' \('` — macOS BWK awk rejects `\(` in the field
        # separator ("illegal primary in regular expression"). Strip the
        # leading indent and the trailing " (UUID) (state)" with sed instead.
        NAME=$( (xcrun simctl list devices available | grep 'iPhone' | head -1 | sed -E 's/^[[:space:]]*//; s/ \([A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\).*$//') || true)
    fi
fi
if [ -z "$NAME" ]; then
    echo "✗ No available iPhone simulator found — create one or pass a name:" >&2
    echo "    Scripts/run-all-tests.sh \"<simulator name>\"" >&2
    exit 1
fi

# UDID from the AVAILABLE list — the destination uses id= (see below), so a
# same-named device on an older runtime must never win over the available one.
UDID=$(xcrun simctl list devices available | grep -F "$NAME (" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1 || true)
if [ -z "$UDID" ]; then
    echo "✗ Simulator \"$NAME\" not found — list candidates with: xcrun simctl list devices available" >&2
    exit 1
fi
echo "▸ Simulator: $NAME ($UDID)"

# --- Resolve the PACKAGE's own workspace — NOT the repo-root SC.xcworkspace.
# Through Examples.xcodeproj only the linked PRODUCT ("BasicList") is a
# blueprint, so the SC workspace's "BasicList" scheme has NO test action
# ("not currently configured for the test action" / "no test bundles"). The
# package workspace (.swiftpm/xcode/package.xcworkspace) autogenerates the
# scheme WITH the test action. Its contents.xcworkspacedata is gitignored —
# recreate it so fresh clones and CI work out of the box.
SWIFTPM_WS=".swiftpm/xcode/package.xcworkspace"
if [ ! -f "$SWIFTPM_WS/contents.xcworkspacedata" ]; then
    mkdir -p "$SWIFTPM_WS"
    cat > "$SWIFTPM_WS/contents.xcworkspacedata" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
XML
fi

# --- Enable accessibility on the simulator (interaction suite needs it)
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility AccessibilityEnabled -bool YES
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool YES
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility AuditInspectionModeEnabled -bool YES

# --- Legs (same isolation as CI; logs go to a temp dir, tail on failure)
LOG_DIR=$(mktemp -d)
run_leg() {
    local title="$1" log="$2"; shift 2
    echo "▸ $title"
    if ! "$@" > "$log" 2>&1; then
        echo "✗ $title — FAILED, last 40 lines of $log:"
        tail -40 "$log"
        exit 1
    fi
    echo "✓ $title"
}

run_leg "Host suites (swift test)" \
    "$LOG_DIR/hostsuites.log" \
    swift test

# Destinations resolve by UDID, not name: a name= destination implies
# `OS:latest`, which silently mismatches any device pinned to an older
# runtime (e.g. an iOS 18.5 floor-verification device) — "no available
# devices matched". id= is exact and immune to name collisions.
run_leg "LoadMore simulator suite" \
    "$LOG_DIR/loadmore.log" \
    xcodebuild test -workspace "$SWIFTPM_WS" -scheme BasicList \
        -destination "platform=iOS Simulator,id=$UDID" \
        -only-testing:BasicListTests/LoadMoreSimulatorTests

run_leg "Interaction simulator suite" \
    "$LOG_DIR/interaction.log" \
    xcodebuild test -workspace "$SWIFTPM_WS" -scheme BasicList \
        -destination "platform=iOS Simulator,id=$UDID" \
        -only-testing:BasicListTests/InteractionSimulatorTests

echo "ALL GREEN — host suites + LoadMore + Interaction on $NAME"
