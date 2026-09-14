#!/usr/bin/env bash
set -euo pipefail

user_name="$1"
user_home="$2"
layout="${3:-native}"
case "$layout" in
  native) zotero_home="$user_home" ;;
  snap) zotero_home="$user_home/snap/zotero-snap/common" ;;
  *) printf 'Unknown Zotero layout: %s\n' "$layout" >&2; exit 2 ;;
esac
profile_root="$zotero_home/.zotero/zotero"
profiles_ini="$profile_root/profiles.ini"
data_dir="$zotero_home/Zotero"
# JavaScript strings must remain valid even when the home contains quotes.
data_dir_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$data_dir")"

mkdir -p "$profile_root"
mkdir -p "$data_dir"

if [ ! -f "$profiles_ini" ]; then
  cat > "$profiles_ini" <<'EOF'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default
IsRelative=1
Path=osworld.default
Default=1
EOF
fi

mapfile -t relative_profiles < <(awk -F= '/^Path=/ {print $2}' "$profiles_ini" | sed '/^$/d')

if [ "${#relative_profiles[@]}" -eq 0 ]; then
  relative_profiles=("osworld.default")
fi

for profile in "${relative_profiles[@]}"; do
  case "$profile" in
    /*) profile_dir="$profile" ;;
    *) profile_dir="$profile_root/$profile" ;;
  esac
  mkdir -p "$profile_dir"
  for pref_file in "$profile_dir/prefs.js" "$profile_dir/user.js"; do
    touch "$pref_file"
    grep -vE 'browser\.laterrun\.enabled|extensions\.zotero\.dataDir|extensions\.zotero\.firstRun2|extensions\.zotero\.firstRun\.skipFirefoxProfileAccessCheck|extensions\.zotero\.httpServer\.(localAPI\.)?enabled|extensions\.zotero\.useDataDir|extensions\.zoteroOpenOfficeIntegration\.skipInstallation' "$pref_file" > "$pref_file.tmp" || true
    cat >> "$pref_file.tmp" <<EOF
user_pref("browser.laterrun.enabled", false);
user_pref("extensions.zotero.dataDir", $data_dir_json);
user_pref("extensions.zotero.firstRun.skipFirefoxProfileAccessCheck", true);
user_pref("extensions.zotero.firstRun2", false);
user_pref("extensions.zotero.httpServer.enabled", true);
user_pref("extensions.zotero.httpServer.localAPI.enabled", true);
user_pref("extensions.zotero.useDataDir", true);
user_pref("extensions.zoteroOpenOfficeIntegration.skipInstallation", true);
EOF
    mv "$pref_file.tmp" "$pref_file"
  done
done

chown -R "$user_name:$(id -gn "$user_name")" "$zotero_home/.zotero"
chown -R "$user_name:$(id -gn "$user_name")" "$data_dir"
if [ "$layout" = snap ]; then
  chown "$user_name:$(id -gn "$user_name")" "$user_home/snap" "$user_home/snap/zotero-snap" "$zotero_home"
fi
