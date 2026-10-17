#!/usr/bin/env bash
# Bundle Nuclear Winter as a debug APK signed with the Android debug keystore.
# Output: releases/nuclear-winter.apk (path is overridable via APK_OUT).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-"$HOME/android-sdk"}}"
JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
export JAVA_HOME
export ANDROID_SDK_ROOT="$SDK"
export ANDROID_HOME="$SDK"

TEMPLATE_VERSION="4.4.1.stable"
TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATES:-"$HOME/.local/share/godot/export_templates/$TEMPLATE_VERSION"}"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
BUILD_TOOLS="34.0.0"
PLATFORM="android-34"

APK_OUT="${APK_OUT:-"$ROOT/releases/nuclear-winter.apk"}"
KEYSTORE="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-"$HOME/.android/debug.keystore"}"
KEY_ALIAS="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
KEY_PASS="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "missing required command: $1" >&2
		exit 1
	fi
}

need "$GODOT"
need java
need keytool
need curl
need unzip

install_templates() {
	if [[ -f "$TEMPLATE_DIR/android_debug.apk" && -f "$TEMPLATE_DIR/android_release.apk" ]]; then
		return
	fi
	echo "Installing Godot Android export templates into $TEMPLATE_DIR"
	local tmp
	tmp="$(mktemp -d)"
	curl -fL --retry 3 -o "$tmp/templates.tpz" "$TEMPLATE_URL"
	mkdir -p "$TEMPLATE_DIR"
	unzip -q -o "$tmp/templates.tpz" -d "$tmp"
	# The archive contains a templates/ directory.
	if [[ -d "$tmp/templates" ]]; then
		cp -a "$tmp/templates/." "$TEMPLATE_DIR/"
	else
		cp -a "$tmp/." "$TEMPLATE_DIR/"
	fi
	rm -rf "$tmp"
	if [[ ! -f "$TEMPLATE_DIR/android_debug.apk" ]]; then
		echo "android_debug.apk was not found after extracting export templates" >&2
		exit 1
	fi
}

install_sdk() {
	if [[ -x "$SDK/build-tools/$BUILD_TOOLS/apksigner" && -d "$SDK/platforms/$PLATFORM" ]]; then
		return
	fi
	echo "Installing Android SDK build-tools and platform into $SDK"
	local tmp
	tmp="$(mktemp -d)"
	curl -fL --retry 3 -o "$tmp/cmdline-tools.zip" "$CMDLINE_URL"
	mkdir -p "$SDK/cmdline-tools"
	unzip -q -o "$tmp/cmdline-tools.zip" -d "$tmp"
	rm -rf "$SDK/cmdline-tools/latest"
	mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"
	rm -rf "$tmp"
	yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null || true
	"$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
		"platform-tools" "build-tools;$BUILD_TOOLS" "platforms;$PLATFORM"
}

install_keystore() {
	if [[ -f "$KEYSTORE" ]]; then
		return
	fi
	echo "Creating Android debug keystore at $KEYSTORE"
	mkdir -p "$(dirname "$KEYSTORE")"
	keytool -genkeypair -v \
		-keystore "$KEYSTORE" \
		-storepass "$KEY_PASS" \
		-alias "$KEY_ALIAS" \
		-keypass "$KEY_PASS" \
		-keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US"
}

write_editor_settings() {
	local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
	local settings="$config_dir/editor_settings-4.4.tres"
	mkdir -p "$config_dir"
	python3 - "$settings" "$SDK" "$JAVA_HOME" "$KEYSTORE" "$KEY_ALIAS" "$KEY_PASS" <<'PY'
import pathlib, re, sys
path, sdk, java_home, keystore, alias, password = sys.argv[1:]
updates = {
    "export/android/android_sdk_path": sdk,
    "export/android/java_sdk_path": java_home,
    "export/android/debug_keystore": keystore,
    "export/android/debug_keystore_user": alias,
    "export/android/debug_keystore_pass": password,
}
file = pathlib.Path(path)
if file.exists():
    text = file.read_text()
else:
    text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
if "[resource]" not in text:
    text += "\n[resource]\n"
for key, value in updates.items():
    line = '%s = "%s"' % (key, value.replace("\\", "\\\\").replace('"', '\\"'))
    pattern = re.compile(r"(?m)^%s = .*$" % re.escape(key))
    if pattern.search(text):
        text = pattern.sub(line, text, count=1)
    else:
        text = text.replace("[resource]\n", "[resource]\n%s\n" % line, 1)
file.write_text(text)
PY
}

install_templates
install_sdk
install_keystore
write_editor_settings

mkdir -p "$(dirname "$APK_OUT")"
echo "Exporting debug APK to $APK_OUT"
(
	cd "$ROOT/godot"
	"$GODOT" --headless --export-debug "Android" "$APK_OUT"
)

if [[ ! -f "$APK_OUT" ]]; then
	echo "export finished but $APK_OUT is missing" >&2
	exit 1
fi

python3 - "$APK_OUT" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as zf:
    names = zf.namelist()
missing = [n for n in ("AndroidManifest.xml",) if n not in names]
if missing:
    raise SystemExit("APK is missing %s" % ", ".join(missing))
print("apk_entries=", len(names))
PY

rm -f "$APK_OUT.idsig"
ls -lh "$APK_OUT"
echo "APK ready: $APK_OUT"
