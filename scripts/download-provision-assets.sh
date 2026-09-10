#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$ROOT_DIR/downloads}"
PROVISION_DIR="${PROVISION_DIR:-$DOWNLOAD_DIR/provision}"
DOWNLOAD_MAX_TIME="${DOWNLOAD_MAX_TIME:-900}"
GROUP_VARS_FILE="$ROOT_DIR/ansible/group_vars/all.yml"

for bin in awk curl git sha256sum tar; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$bin" >&2
    exit 1
  }
done

read_yaml_scalar() {
  local key="$1"
  awk -v key="$key" -F': ' '$1 == key { value=$2; gsub(/^"|"$/, "", value); print value; exit }' "$GROUP_VARS_FILE"
}

OSWORLD_SERVER_REPO_URL="${OSWORLD_SERVER_REPO_URL:-$(read_yaml_scalar osworld_server_repo_url)}"
OSWORLD_SERVER_COMMIT="${OSWORLD_SERVER_COMMIT:-$(read_yaml_scalar osworld_server_commit)}"
OSWORLD_SERVER_LOCAL_REPO="${OSWORLD_SERVER_LOCAL_REPO:-/home/adlsdztony/codes/OSWorld-V2/desktop_env/server}"

verify_sha256() {
  local checksum="$1"
  local path="$2"
  local expected="${checksum#sha256:}"
  local actual

  [ -f "$path" ] || return 1
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [ "$actual" = "$expected" ]
}

download_checked() {
  local url="$1"
  local checksum="$2"
  local dest="$3"
  local insecure="${4:-false}"
  local tmp="$dest.part"
  local curl_args=(
    --location
    --fail
    --retry 3
    --connect-timeout 20
    --max-time "$DOWNLOAD_MAX_TIME"
  )

  mkdir -p "$(dirname "$dest")"

  if verify_sha256 "$checksum" "$dest"; then
    printf 'Using existing %s\n' "$dest"
    return
  fi

  if [ "$insecure" = "true" ]; then
    curl_args+=(--insecure)
  fi

  rm -f "$tmp"
  printf 'Downloading %s\n' "$dest"
  curl "${curl_args[@]}" "$url" -o "$tmp"

  if ! verify_sha256 "$checksum" "$tmp"; then
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
    printf 'Checksum mismatch for %s: expected %s, got %s\n' "$dest" "${checksum#sha256:}" "$actual" >&2
    rm -f "$tmp"
    exit 1
  fi

  mv "$tmp" "$dest"
}

download_osworld_server_archive() {
  local dest="$DOWNLOAD_DIR/osworld_server/osworld-server-$OSWORLD_SERVER_COMMIT.tar.gz"
  local tmp="$dest.part"
  local clone_dir

  mkdir -p "$(dirname "$dest")"

  if [ -f "$dest" ] && tar -tzf "$dest" >/dev/null 2>&1; then
    printf 'Using existing %s\n' "$dest"
    return
  fi

  rm -f "$tmp"

  if [ -d "$OSWORLD_SERVER_LOCAL_REPO/.git" ] \
    && git -C "$OSWORLD_SERVER_LOCAL_REPO" cat-file -e "$OSWORLD_SERVER_COMMIT^{commit}" 2>/dev/null; then
    printf 'Archiving OSWorld server %s from %s\n' "$OSWORLD_SERVER_COMMIT" "$OSWORLD_SERVER_LOCAL_REPO"
    git -C "$OSWORLD_SERVER_LOCAL_REPO" archive \
      --format=tar.gz \
      --prefix=osworld-server/ \
      -o "$tmp" \
      "$OSWORLD_SERVER_COMMIT"
  else
    clone_dir="$(mktemp -d)"
    cleanup_clone() {
      rm -rf "$clone_dir"
    }
    trap cleanup_clone RETURN
    printf 'Cloning OSWorld server from %s\n' "$OSWORLD_SERVER_REPO_URL"
    git clone --no-checkout "$OSWORLD_SERVER_REPO_URL" "$clone_dir/repo"
    git -C "$clone_dir/repo" archive \
      --format=tar.gz \
      --prefix=osworld-server/ \
      -o "$tmp" \
      "$OSWORLD_SERVER_COMMIT"
  fi

  tar -tzf "$tmp" >/dev/null
  mv "$tmp" "$dest"
  printf 'OSWorld server archive: %s\n' "$dest"
}

download_snap_package() {
  local name="$1"
  local revision="${2:-}"
  local expected_sha256="${3:-}"
  local revision_args=()
  if [ -n "$revision" ]; then
    revision_args=("--revision=$revision")
  fi
  local dest_dir="$PROVISION_DIR/snaps"
  local snap_dest="$dest_dir/$name.snap"
  local assert_dest="$dest_dir/$name.assert"
  local tmp_dir
  local snap_file
  local assert_file

  mkdir -p "$dest_dir"

  if [ -f "$snap_dest" ] && [ -f "$assert_dest" ]; then
    if [ -n "$expected_sha256" ]; then
      printf '%s  %s\n' "$expected_sha256" "$snap_dest" | sha256sum --check --status
    fi
    printf 'Using existing %s and %s\n' "$snap_dest" "$assert_dest"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    printf 'Skipping %s snap cache because snap is not installed on the controller\n' "$name" >&2
    return
  fi

  tmp_dir="$(mktemp -d)"
  (
    cd "$tmp_dir"
    snap download "$name" "${revision_args[@]}"
  )

  snap_file="$(find "$tmp_dir" -maxdepth 1 -type f -name "${name}_*.snap" | sort | head -n 1)"
  assert_file="$(find "$tmp_dir" -maxdepth 1 -type f -name "${name}_*.assert" | sort | head -n 1)"

  if [ -z "$snap_file" ] || [ -z "$assert_file" ]; then
    printf 'snap download did not produce %s snap/assert files\n' "$name" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  mv "$snap_file" "$snap_dest"
  mv "$assert_file" "$assert_dest"
  rm -rf "$tmp_dir"
  if [ -n "$expected_sha256" ]; then
    printf '%s  %s\n' "$expected_sha256" "$snap_dest" | sha256sum --check --status
  fi
  printf 'Snap package: %s\n' "$snap_dest"
  printf 'Snap assertion: %s\n' "$assert_dest"
}

download_checked \
  "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.10.6/obsidian_1.10.6_amd64.deb" \
  "sha256:7e2fcf3fa6da54715d88a17ac906c87ca397c9d1e15ac6a0f6ba74f097a749d6" \
  "$PROVISION_DIR/deb/obsidian_1.10.6_amd64.deb"

download_checked \
  "https://dl3.xmind.net/Xmind-for-Linux-amd64bit-26.01.03145-202510170359.deb" \
  "sha256:87bab10dfdb5f7eb7ca0093c20006ceccc9ab0d7772bf3c033a6bbf64c9a2ddc" \
  "$PROVISION_DIR/deb/Xmind-for-Linux-amd64bit-26.01.03145-202510170359.deb"

download_checked \
  "https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11723/wps-office_11.1.0.11723.XA_amd64.deb" \
  "sha256:fe6326210f69d94efdbf2728914d293036be391b93a614f58cd0e1ff1d4923b3" \
  "$PROVISION_DIR/deb/wps-office_11.1.0.11723.XA_amd64.deb"

download_checked \
  "https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/12.2.0.23131/500.1001/WPSOffice_12.2.0.23131.exe" \
  "sha256:116ce81023c7b088952005dcb0eb4300a5abb53055076458ab49b04acae936a0" \
  "$PROVISION_DIR/windows/WPSOffice_12.2.0.23131.exe"

download_checked \
  "https://downloads.sourceforge.net/project/shotcut/v26.2.26/shotcut-linux-x86_64-26.2.26.AppImage" \
  "sha256:837e0306fa970e2f2627317859c10b83a3f4728e5cd1918995d29e5284b34415" \
  "$PROVISION_DIR/appimages/shotcut-26.2.26.AppImage"

download_checked \
  "https://download.kde.org/stable/labplot/labplot-2.12.1-x86_64.AppImage" \
  "sha256:1b700d60b3297a987022cfc532e413b8211ef917059a21155d8b5604f3012a82" \
  "$PROVISION_DIR/appimages/labplot-2.12.1-x86_64.AppImage" \
  "true"

download_checked \
  "https://github.com/musescore/MuseScore/releases/download/v4.6.0/MuseScore-Studio-4.6.0.252730944-x86_64.AppImage" \
  "sha256:8b6570311a245495c0d93541a3737e4ca118a1450337655e06b3fd8d18527483" \
  "$PROVISION_DIR/appimages/MuseScore-Studio-4.6.0.252730944-x86_64.AppImage"

download_checked \
  "https://download.blender.org/release/Blender5.0/blender-5.0.0-linux-x64.tar.xz" \
  "sha256:9de96e81432afba9c0a715c7233f1eff616705b75226dc5d0fa2708ddfb0e525" \
  "$PROVISION_DIR/archives/blender-5.0.0-linux-x64.tar.xz"

download_checked \
  "https://download.zotero.org/client/release/8.0.2/Zotero-8.0.2_linux-x86_64.tar.xz" \
  "sha256:846c79f1c3c54706c29229a12b7a237f080613c1752f0734ad84c92e4ae9f170" \
  "$PROVISION_DIR/archives/Zotero-8.0.2_linux-x86_64.tar.xz"

download_checked \
  "https://dlcf.reaper.fm/7.x/reaper764_linux_x86_64.tar.xz" \
  "sha256:9b0da6fe54cc0db835812da0f7df1e35b028f716f7199e3322f31144d0f3f399" \
  "$PROVISION_DIR/archives/reaper764_linux_x86_64.tar.xz"

"$ROOT_DIR/scripts/download-wps-fonts.sh"
"$ROOT_DIR/scripts/download-qemu-ssh-debs.sh"
download_snap_package "audacity"
download_snap_package "zotero-snap" "128" "9d4cd8ab1bcba8bd98e042f7f6b0ee4303f422aa04ab1c3ca100c99ff68e7713"
download_osworld_server_archive

printf 'Provision assets cached under %s\n' "$DOWNLOAD_DIR"
