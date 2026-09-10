#!/usr/bin/env bash
set -euo pipefail

OSWORLD_USER="${OSWORLD_USER:-user}"
OSWORLD_HOME="$(getent passwd "$OSWORLD_USER" | awk -F: '{print $6}')"
APPIMAGE_DIR="${APPIMAGE_DIR:-/opt/osworld-appimages}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label expected to contain '$needle', got '$haystack'"
}

assert_file_sha256() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "$path sha256 expected $expected, got $actual"
}

assert_dpkg_version() {
  local package="$1"
  local expected="$2"
  local version
  version="$(dpkg-query -W -f='${Version}' "$package")"
  assert_contains "$version" "$expected" "$package version"
}

assert_desktop_icon() {
  local desktop_name="$1"
  local icon_name="$2"
  local icon_path="$3"
  local desktop_file="/usr/share/applications/$desktop_name.desktop"
  grep -q "^Icon=$icon_name$" "$desktop_file" || fail "$desktop_file missing Icon=$icon_name"
  test -s "$icon_path" || fail "$icon_path missing or empty"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  test -f "$path" || fail "$path missing"
  grep -Fq "$needle" "$path" || fail "$path missing expected content: $needle"
}

command -v node >/dev/null 2>&1 || fail "node command missing"
command -v npm >/dev/null 2>&1 || fail "npm command missing"
command -v xclip >/dev/null 2>&1 || fail "xclip command missing"
command -v xdotool >/dev/null 2>&1 || fail "xdotool command missing"
node --version | grep -Eq '^v[0-9]+' || fail "node --version did not return a version"
npm --version | grep -Eq '^[0-9]+' || fail "npm --version did not return a version"
xclip -version >/dev/null 2>&1 || fail "xclip version check failed"
xdotool -v >/dev/null 2>&1 || fail "xdotool version check failed"

assert_dpkg_version obsidian "1.10.6"
assert_dpkg_version xmind-vana "26.1.3145"
assert_dpkg_version wps-office "11.1.0.11723"

audacity_version="$(snap list audacity | awk 'NR==2 {print $2}')"
[[ "$audacity_version" == "3.7.5" ]] || fail "audacity snap version expected 3.7.5, got $audacity_version"

assert_file_sha256 "$APPIMAGE_DIR/shotcut-26.2.26.AppImage" "837e0306fa970e2f2627317859c10b83a3f4728e5cd1918995d29e5284b34415"
grep -q '^version=26.2.26$' "$APPIMAGE_DIR/shotcut.version" || fail "Shotcut version manifest missing 26.2.26"

assert_file_sha256 "$APPIMAGE_DIR/labplot-2.12.1-x86_64.AppImage" "1b700d60b3297a987022cfc532e413b8211ef917059a21155d8b5604f3012a82"
grep -q '^version=2.12.1$' "$APPIMAGE_DIR/labplot.version" || fail "LabPlot version manifest missing 2.12.1"

assert_file_sha256 "$APPIMAGE_DIR/MuseScore-Studio-4.6.0.252730944-x86_64.AppImage" "8b6570311a245495c0d93541a3737e4ca118a1450337655e06b3fd8d18527483"
grep -q '^version=4.6$' "$APPIMAGE_DIR/musescore.version" || fail "MuseScore version manifest missing 4.6"

blender_version="$(/usr/local/bin/blender --version | head -n 1)"
assert_contains "$blender_version" "Blender 5.0.0" "Blender version"

zotero_version="$(awk -F= '/^Version=/ {print $2}' /opt/zotero-8.0.2/Zotero_linux-x86_64/app/application.ini)"
[[ "$zotero_version" == "8.0.2" ]] || fail "Zotero version expected 8.0.2, got $zotero_version"

# The Docker provider boots a full VM; its tasks call snap run zotero-snap.
zotero_snap="$(snap list zotero-snap | awk 'NR==2 {print $2 " " $3}')"
[[ "$zotero_snap" == "9.0.1 128" ]] || fail "Zotero snap expected 9.0.1 revision 128, got $zotero_snap"
assert_file_sha256 /var/lib/snapd/snaps/zotero-snap_128.snap "9d4cd8ab1bcba8bd98e042f7f6b0ee4303f422aa04ab1c3ca100c99ff68e7713"
grep -qx 'confinement: strict' /snap/zotero-snap/current/meta/snap.yaml \
  || fail "Zotero snap must use strict confinement"
snap list zotero-snap | awk 'NR==2 {print $NF}' | grep -Eq '(^|,)devmode(,|$)|(^|,)classic(,|$)' \
  && fail "Zotero snap confinement must not be disabled"
python3 /usr/local/sbin/initialize-zotero "$OSWORLD_USER" --layout snap

assert_desktop_icon shotcut shotcut /usr/share/icons/hicolor/128x128/apps/shotcut.png
assert_desktop_icon labplot labplot /usr/share/icons/hicolor/scalable/apps/labplot.svg
assert_desktop_icon musescore musescore /usr/share/icons/hicolor/512x512/apps/musescore.png
assert_desktop_icon blender blender /usr/share/icons/hicolor/scalable/apps/blender.svg
assert_desktop_icon zotero zotero /usr/share/icons/hicolor/128x128/apps/zotero.png

grep -q '^version=7.64$' "$OSWORLD_HOME/opt/REAPER/.osworld-version" || fail "REAPER version manifest missing 7.64"
test -x "$OSWORLD_HOME/opt/REAPER/reaper" || fail "REAPER binary missing"

jq -e '.SafeBrowsingProtectionLevel == 0 and .SafeBrowsingEnabled == false' \
  /etc/opt/chrome/policies/managed/osworld-safe-browsing.json >/dev/null \
  || fail "Chrome Safe Browsing policy is not no-protection"

find "$OSWORLD_HOME/.zotero/zotero" -type f \( -name prefs.js -o -name user.js \) \
  -exec grep -q 'extensions.zotero.httpServer.enabled", true' {} + \
  || fail "Zotero httpServer.enabled preference missing"
find "$OSWORLD_HOME/.zotero/zotero" -type f \( -name prefs.js -o -name user.js \) \
  -exec grep -q 'extensions.zotero.httpServer.localAPI.enabled", true' {} + \
  || fail "Zotero localAPI.enabled preference missing"
find "$OSWORLD_HOME/.zotero/zotero" -type f \( -name prefs.js -o -name user.js \) \
  -exec grep -q 'extensions.zotero.firstRun2", false' {} + \
  || fail "Zotero firstRun2 suppression preference missing"
find "$OSWORLD_HOME/.zotero/zotero" -type f \( -name prefs.js -o -name user.js \) \
  -exec grep -q 'extensions.zoteroOpenOfficeIntegration.skipInstallation", true' {} + \
  || fail "Zotero LibreOffice integration prompt suppression missing"

assert_file_contains "$OSWORLD_HOME/.config/Kingsoft/Office.conf" 'common\AcceptedEULA=true'
assert_file_contains "$OSWORLD_HOME/.config/Kingsoft/Office.conf" 'common\UserInfo\ACUPI=true'
assert_file_contains "$OSWORLD_HOME/.config/Kingsoft/WPSCloud.conf" 'kicUploadSyncSwitch=false'

jq -e '(.acceptedEULAVersions | index("3")) and .lastWelcomeVersion == 11 and .lastWelcomeVersionForUS == 12' \
  "$OSWORLD_HOME/.config/Xmind/Electron v3/vana/state/app.json" >/dev/null \
  || fail "XMind EULA/welcome suppression missing"
jq -e '.sendUsageData == false and .autoUpdateType == "manual"' \
  "$OSWORLD_HOME/.config/Xmind/Electron v3/vana/state/preferences.json" >/dev/null \
  || fail "XMind startup preferences missing"

assert_file_contains "$OSWORLD_HOME/.config/MuseScore/MuseScore4.ini" "hasCompletedFirstLaunchSetup=true"
assert_file_contains "$OSWORLD_HOME/.config/MuseScore/MuseScore4.ini" "skippedVersion=4.6.5"

assert_file_contains "$OSWORLD_HOME/.config/REAPER/reaper.ini" "[nag]"
assert_file_contains "$OSWORLD_HOME/.config/REAPER/reaper.ini" "lastt=4102444800"

audacity_revision="$(snap list audacity | awk 'NR==2 {print $3}')"
audacity_cfg="$OSWORLD_HOME/snap/audacity/$audacity_revision/.config/audacity/audacity.cfg"
assert_file_contains "$audacity_cfg" "IntroOrderStart=2"
assert_file_contains "$audacity_cfg" "ShowSplashScreen=0"

awk '
  tolower($0) ~ /^[[:space:]]*section[[:space:]]+"serverflags"/ { insec=1 }
  insec && tolower($0) ~ /^[[:space:]]*option[[:space:]]+"maxclients"[[:space:]]+"2048"/ { found=1 }
  insec && tolower($0) ~ /^[[:space:]]*endsection/ { insec=0 }
  END { exit found ? 0 : 1 }
' /etc/X11/xorg.conf || fail "Xorg MaxClients 2048 missing"

declare -A mime_defaults=(
  [application/msword]=libreoffice-writer.desktop
  [application/vnd.openxmlformats-officedocument.wordprocessingml.document]=libreoffice-writer.desktop
  [application/vnd.ms-excel]=libreoffice-calc.desktop
  [application/vnd.openxmlformats-officedocument.spreadsheetml.sheet]=libreoffice-calc.desktop
  [application/vnd.ms-powerpoint]=libreoffice-impress.desktop
  [application/vnd.openxmlformats-officedocument.presentationml.presentation]=libreoffice-impress.desktop
  [application/vnd.oasis.opendocument.text]=libreoffice-writer.desktop
  [application/vnd.oasis.opendocument.spreadsheet]=libreoffice-calc.desktop
  [application/vnd.oasis.opendocument.presentation]=libreoffice-impress.desktop
  [application/wps-office.doc]=libreoffice-writer.desktop
  [application/wps-office.docx]=libreoffice-writer.desktop
  [application/wps-office.xls]=libreoffice-calc.desktop
  [application/wps-office.xlsx]=libreoffice-calc.desktop
  [application/wps-office.ppt]=libreoffice-impress.desktop
  [application/wps-office.pptx]=libreoffice-impress.desktop
)

for mime in "${!mime_defaults[@]}"; do
  actual="$(runuser -u "$OSWORLD_USER" -- xdg-mime query default "$mime")"
  [[ "$actual" == "${mime_defaults[$mime]}" ]] || fail "$mime default expected ${mime_defaults[$mime]}, got $actual"
done

fc-list | awk 'BEGIN { IGNORECASE=1 } /Wingdings|Webdings|MT Extra|Symbol/ { found=1 } END { exit found ? 0 : 1 }' \
  || fail "WPS symbol fonts not visible to fc-list"

tilde_leftover="$(find "$OSWORLD_HOME" -mindepth 1 -maxdepth 1 -type d -name '~*' -print -quit)"
[[ -z "$tilde_leftover" ]] || fail "unexpected tilde-prefixed home leftover: $tilde_leftover"
if [ -d "$OSWORLD_HOME/Desktop" ]; then
  wps_shortcut_leftover="$(find "$OSWORLD_HOME/Desktop" -maxdepth 1 -type f -name 'wps-office*.desktop' -print -quit)"
  [[ -z "$wps_shortcut_leftover" ]] || fail "unexpected WPS desktop shortcut leftover: $wps_shortcut_leftover"
fi
test ! -d /var/cache/osworld-delta || fail "/var/cache/osworld-delta provisioning cache was not removed"
test ! -d /opt/osworld-server-src || fail "/opt/osworld-server-src transient clone was not removed"

server_marker=""
for candidate in "$OSWORLD_HOME/server" "$OSWORLD_HOME/osworld/server" /opt/osworld/server /server; do
  if [ -f "$candidate/.osworld-server-commit" ]; then
    server_marker="$candidate/.osworld-server-commit"
    break
  fi
done
[[ -n "$server_marker" ]] || fail "OSWorld server commit marker missing"
server_commit="$(cat "$server_marker")"
[[ "$server_commit" == "a3cc3f0c64e463f020d1a44780307e9b46cbcab1" ]] || fail "OSWorld server commit marker mismatch"
server_dir="$(dirname "$server_marker")"
server_python="$server_dir/.venv/bin/python"
test -x "$server_python" || fail "OSWorld server venv Python missing"
pyperclip_version="$("$server_python" -c "import importlib.metadata; print(importlib.metadata.version('pyperclip'))")"
[[ "$pyperclip_version" == "1.11.0" ]] || fail "pyperclip version expected 1.11.0, got $pyperclip_version"

systemctl is-active --quiet osworld.service || fail "osworld.service is not active"
ss -ltn | awk '$4 ~ /:5000$/ { found=1 } END { exit found ? 0 : 1 }' \
  || fail "osworld.service is not listening on port 5000"
test -x "${server_marker%/.osworld-server-commit}/.venv/bin/python" \
  || fail "OSWorld server virtualenv python missing"

printf 'Smoke checks passed for user %s\n' "$OSWORLD_USER"
