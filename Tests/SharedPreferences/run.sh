#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MODULE_FW_DIR="$ROOT_DIR/build/Build/Products/Release"
RUNTIME_FW_DIR="$ROOT_DIR/export/OpenInTerminal.app/Contents/Frameworks"

if [[ ! -d "$MODULE_FW_DIR/OpenInTerminalCore.framework" ]]; then
  echo "!! Expected built OpenInTerminalCore.framework at $MODULE_FW_DIR/OpenInTerminalCore.framework" >&2
  exit 1
fi
if [[ ! -d "$RUNTIME_FW_DIR/OpenInTerminalCore.framework" ]]; then
  echo "!! Expected embedded OpenInTerminalCore.framework at $RUNTIME_FW_DIR/OpenInTerminalCore.framework" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oit-regression.XXXXXX")"
cleanup() {
  if [[ -x "${WORK_DIR}/host-runner" ]]; then
    "${WORK_DIR}/host-runner" clean >/dev/null 2>&1 || true
  fi
  if [[ -x "${WORK_DIR}/ext-runner" ]]; then
    "${WORK_DIR}/ext-runner" clean >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "==> Compiling SharedPreferences regression runners against OpenInTerminalCore.framework"
xcrun swiftc \
  "$ROOT_DIR/Tests/SharedPreferences/main.swift" \
  -F "$MODULE_FW_DIR" \
  -framework OpenInTerminalCore \
  -Xlinker -rpath -Xlinker "$RUNTIME_FW_DIR" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$ROOT_DIR/Tests/SharedPreferences/HostInfo.plist" \
  -o "$WORK_DIR/host-runner"

xcrun swiftc \
  "$ROOT_DIR/Tests/SharedPreferences/main.swift" \
  -F "$MODULE_FW_DIR" \
  -framework OpenInTerminalCore \
  -Xlinker -rpath -Xlinker "$RUNTIME_FW_DIR" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$ROOT_DIR/Tests/SharedPreferences/ExtensionInfo.plist" \
  -o "$WORK_DIR/ext-runner"

codesign --force --sign - "$MODULE_FW_DIR/OpenInTerminalCore.framework"
codesign --force --sign - "$WORK_DIR/host-runner"
codesign --force --sign - "$WORK_DIR/ext-runner"

LEGACY_PLIST="$WORK_DIR/legacy-group.plist"
SHARED_PLIST="$WORK_DIR/ApplicationScripts/shared-settings.plist"

cat > "$LEGACY_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>FirstSetup</key>
	<true/>
	<key>DefaultTerminal</key>
	<string>Ghostty</string>
	<key>DefaultEditor</key>
	<string>Visual Studio Code</string>
	<key>ContextMenuUseSubmenu</key>
	<true/>
</dict>
</plist>
EOF
plutil -convert binary1 "$LEGACY_PLIST"

echo "==> [1/5] Host migration from legacy plist + live preference update"
OIT_LEGACY_PREFERENCES_PATH="$LEGACY_PLIST" \
OIT_SHARED_PREFERENCES_PATH="$SHARED_PLIST" \
  "$WORK_DIR/host-runner" migrate-and-write

# Remove legacy plist before relaunch to prove UserDefaults.standard persisted natively
rm -f "$LEGACY_PLIST"

echo "==> [2/5] Host relaunch persistence + Finder Alias + Warp URI + AppleScript compile checks"
OIT_SHARED_PREFERENCES_PATH="$SHARED_PLIST" \
  "$WORK_DIR/host-runner" host-relaunch-verify

echo "==> [3/5] Sandboxed extension snapshot sync verification"
OIT_FORCE_EXTENSION_MODE=1 \
OIT_SHARED_PREFERENCES_PATH="$SHARED_PLIST" \
  "$WORK_DIR/ext-runner" extension-verify

# Recreate legacy plist to verify Reset Preferences does NOT re-import stale legacy data
cat > "$LEGACY_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>FirstSetup</key>
	<true/>
	<key>DefaultTerminal</key>
	<string>Ghostty</string>
</dict>
</plist>
EOF

echo "==> [4/5] Host Reset Preferences verification"
OIT_LEGACY_PREFERENCES_PATH="$LEGACY_PLIST" \
OIT_SHARED_PREFERENCES_PATH="$SHARED_PLIST" \
  "$WORK_DIR/host-runner" host-reset

echo "==> [5/5] Extension snapshot sync after Reset Preferences"
OIT_FORCE_EXTENSION_MODE=1 \
OIT_SHARED_PREFERENCES_PATH="$SHARED_PLIST" \
  "$WORK_DIR/ext-runner" extension-after-reset

echo "==> All regression checks PASSED!"
