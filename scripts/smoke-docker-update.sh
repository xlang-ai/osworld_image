#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-osworld-xfce}"
EXPECTED_SERVER_COMMIT="${EXPECTED_SERVER_COMMIT:-a3cc3f0c64e463f020d1a44780307e9b46cbcab1}"

docker exec "$CONTAINER_NAME" bash -lc '
  set -euo pipefail

  expected_server_commit="'"$EXPECTED_SERVER_COMMIT"'"

  fail() {
    printf "FAIL: %s\n" "$*" >&2
    exit 1
  }

  marker="/home/${OSWORLD_USER:-user}/server/.osworld-server-commit"
  test -f "$marker" || fail "OSWorld server commit marker missing"
  test "$(cat "$marker")" = "$expected_server_commit" || fail "OSWorld server commit marker mismatch"

  dpkg-query -W -f="\${Version}\n" obsidian | grep -q "1.10.6" || fail "Obsidian version mismatch"
  dpkg-query -W -f="\${Version}\n" xmind-vana | grep -q "26.1.3145" || fail "XMind version mismatch"
  dpkg-query -W -f="\${Version}\n" wps-office | grep -q "11.1.0.11723" || fail "WPS version mismatch"

  if dpkg-query -W -f="\${Status}" snapd 2>/dev/null | grep -q "install ok installed"; then
    fail "snapd should not be installed in the Docker update image"
  fi

  for required in blender zotero reaper shotcut labplot musescore; do
    command -v "$required" >/dev/null 2>&1 || fail "$required is missing from PATH"
  done

  command -v node >/dev/null 2>&1 || fail "node command missing"
  command -v npm >/dev/null 2>&1 || fail "npm command missing"
  node --version | grep -Eq "^v[0-9]+" || fail "node --version did not return a version"
  npm --version | grep -Eq "^[0-9]+" || fail "npm --version did not return a version"

  test "$(basename "$(readlink /proc/1/exe)")" = tini || fail "PID 1 is not tini"
  supervisorctl status
  pgrep -x Xvfb >/dev/null || fail "Xvfb is not running"
  pgrep -f xfce4-session >/dev/null || fail "XFCE session is not running"
  xdpyinfo -display "${DISPLAY:-:0}" >/dev/null || fail "DISPLAY is not usable"

  server_running=0
  for _ in $(seq 1 30); do
    if supervisorctl status osworld-server | grep -q RUNNING; then
      server_running=1
      break
    fi
    sleep 1
  done
  test "$server_running" = "1" || fail "osworld-server is not running"

  screenshot_file="$(mktemp)"
  screenshot_ok=0
  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:5000/screenshot -o "$screenshot_file"; then
      screenshot_ok=1
      break
    fi
    sleep 1
  done
  test "$screenshot_ok" = "1" || fail "screenshot endpoint failed"
  head -c 8 "$screenshot_file" | od -An -tx1 | tr -d " \n" | grep -qi "^89504e470d0a1a0a$" \
    || fail "screenshot endpoint did not return a PNG"
  rm -f "$screenshot_file"

  user_name="${OSWORLD_USER:-user}"
  user_home="$(getent passwd "$user_name" | awk -F: "{print \$6}")"
  user_id="$(id -u "$user_name")"
  user_env=(
    HOME="$user_home"
    USER="$user_name"
    LOGNAME="$user_name"
    DISPLAY="${DISPLAY:-:0}"
    XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
    GDK_BACKEND="${GDK_BACKEND:-x11}"
    XDG_RUNTIME_DIR="/run/user/$user_id"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus"
  )

  launch_as_user() {
    sudo -u "$user_name" env "${user_env[@]}" "$@"
  }

  # Native Docker has no snapd; verify the tarball application and database.
  python3 /usr/local/sbin/initialize-zotero "$user_name" --layout native

  launch_as_user xdg-settings get default-web-browser | grep -qx "google-chrome.desktop" \
    || fail "Chrome is not the default browser"

  declare -A mime_defaults=(
    [application/msword]=libreoffice-writer.desktop
    [application/vnd.ms-word]=libreoffice-writer.desktop
    [application/x-msword]=libreoffice-writer.desktop
    [application/msword-template]=libreoffice-writer.desktop
    [application/rtf]=libreoffice-writer.desktop
    [text/rtf]=libreoffice-writer.desktop
    [application/vnd.openxmlformats-officedocument.wordprocessingml.document]=libreoffice-writer.desktop
    [application/vnd.openxmlformats-officedocument.wordprocessingml.template]=libreoffice-writer.desktop
    [application/vnd.ms-excel]=libreoffice-calc.desktop
    [application/msexcel]=libreoffice-calc.desktop
    [application/x-msexcel]=libreoffice-calc.desktop
    [application/x-ms-excel]=libreoffice-calc.desktop
    [application/x-dos_ms_excel]=libreoffice-calc.desktop
    [application/x-excel]=libreoffice-calc.desktop
    [application/x-xls]=libreoffice-calc.desktop
    [application/xls]=libreoffice-calc.desktop
    [application/excel]=libreoffice-calc.desktop
    [application/csv]=libreoffice-calc.desktop
    [text/csv]=libreoffice-calc.desktop
    [text/spreadsheet]=libreoffice-calc.desktop
    [text/comma-separated-values]=libreoffice-calc.desktop
    [text/tab-separated-values]=libreoffice-calc.desktop
    [application/vnd.openxmlformats-officedocument.spreadsheetml.sheet]=libreoffice-calc.desktop
    [application/vnd.openxmlformats-officedocument.spreadsheetml.template]=libreoffice-calc.desktop
    [application/vnd.ms-powerpoint]=libreoffice-impress.desktop
    [application/mspowerpoint]=libreoffice-impress.desktop
    [application/vnd.mspowerpoint]=libreoffice-impress.desktop
    [application/powerpoint]=libreoffice-impress.desktop
    [application/x-mspowerpoint]=libreoffice-impress.desktop
    [application/vnd.openxmlformats-officedocument.presentationml.presentation]=libreoffice-impress.desktop
    [application/vnd.openxmlformats-officedocument.presentationml.template]=libreoffice-impress.desktop
    [application/vnd.openxmlformats-officedocument.presentationml.slideshow]=libreoffice-impress.desktop
    [application/vnd.openxmlformats-officedocument.presentationml.slide]=libreoffice-impress.desktop
    [application/vnd.oasis.opendocument.text]=libreoffice-writer.desktop
    [application/vnd.oasis.opendocument.text-template]=libreoffice-writer.desktop
    [application/vnd.oasis.opendocument.spreadsheet]=libreoffice-calc.desktop
    [application/vnd.oasis.opendocument.spreadsheet-template]=libreoffice-calc.desktop
    [application/vnd.oasis.opendocument.presentation]=libreoffice-impress.desktop
    [application/vnd.oasis.opendocument.presentation-template]=libreoffice-impress.desktop
    [application/wps-office.doc]=libreoffice-writer.desktop
    [application/wps-office.docx]=libreoffice-writer.desktop
    [application/wps-office.dot]=libreoffice-writer.desktop
    [application/wps-office.dotx]=libreoffice-writer.desktop
    [application/wps-office.xls]=libreoffice-calc.desktop
    [application/wps-office.xlsx]=libreoffice-calc.desktop
    [application/wps-office.xlt]=libreoffice-calc.desktop
    [application/wps-office.xltx]=libreoffice-calc.desktop
    [application/wps-office.ppt]=libreoffice-impress.desktop
    [application/wps-office.pptx]=libreoffice-impress.desktop
    [application/wps-office.pot]=libreoffice-impress.desktop
    [application/wps-office.potx]=libreoffice-impress.desktop
  )

  for mime in "${!mime_defaults[@]}"; do
    actual="$(launch_as_user xdg-mime query default "$mime")"
    test "$actual" = "${mime_defaults[$mime]}" \
      || fail "$mime default expected ${mime_defaults[$mime]}, got $actual"
  done

  printf "Docker update smoke checks passed\n"
'
