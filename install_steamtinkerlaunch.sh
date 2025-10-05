#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f "$0")

if [[ $EUID -ne 0 ]]; then
  if command -v pkexec >/dev/null 2>&1; then
    exec pkexec env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" bash "$SCRIPT_PATH" "$@"
  else
    echo "Error: pkexec not found. Run the script as root." >&2
    exit 1
  fi
fi

DISPLAY_ORIG=${DISPLAY:-}
XAUTHORITY_ORIG=${XAUTHORITY:-}

CALLING_USER="root"
if [[ -n ${PKEXEC_UID:-} ]]; then
  if id -un "$PKEXEC_UID" >/dev/null 2>&1; then
    CALLING_USER=$(id -un "$PKEXEC_UID")
  fi
elif [[ -n ${SUDO_USER:-} ]]; then
  CALLING_USER="$SUDO_USER"
fi

CALLING_HOME=$(getent passwd "$CALLING_USER" | cut -d: -f6 || true)
if [[ -z ${CALLING_HOME:-} ]]; then
  CALLING_HOME="${HOME:-/root}"
fi

PREFIX_DEFAULT="/usr/local"
BRANCH_DEFAULT="master"
YAD_VERSION_DEFAULT="latest"
YAD_MIN_VERSION="7.2"

usage() {
  local self
  self=$(basename "$0")
  cat <<USAGE
Usage: ${self} [options]

Options:
  --prefix DIR         Install prefix for SteamTinkerLaunch (default: /usr/local)
  --branch NAME        Git branch or tag of SteamTinkerLaunch (default: master)
  --yad-prefix DIR     Install prefix for Yad (default: same as --prefix)
  --yad-version VER    Yad version to install (default: latest release)
  -h, --help           Show this message and exit
USAGE
}

PREFIX="$PREFIX_DEFAULT"
BRANCH="$BRANCH_DEFAULT"
YAD_PREFIX=""
YAD_PREFIX_SET=false
YAD_VERSION="$YAD_VERSION_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -lt 2 ]] && { echo "Missing value for --prefix" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --branch)
      [[ $# -lt 2 ]] && { echo "Missing value for --branch" >&2; exit 1; }
      BRANCH="$2"
      shift 2
      ;;
    --yad-prefix)
      [[ $# -lt 2 ]] && { echo "Missing value for --yad-prefix" >&2; exit 1; }
      YAD_PREFIX="$2"
      YAD_PREFIX_SET=true
      shift 2
      ;;
    --yad-version)
      [[ $# -lt 2 ]] && { echo "Missing value for --yad-version" >&2; exit 1; }
      YAD_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! $YAD_PREFIX_SET; then
  YAD_PREFIX="$PREFIX"
fi

APT_PACKAGES=(
  autoconf
  automake
  autopoint
  build-essential
  curl
  gawk
  git
  gettext
  intltool
  libgdk-pixbuf-2.0-dev
  libglib2.0-bin
  libglib2.0-dev
  libgtk-3-dev
  libgtk-3-bin
  libpango1.0-dev
  libtool
  libxml2-dev
  pkg-config
  procps
  unzip
  wget
  x11-utils
  x11-xserver-utils
  xdotool
  vim-common
  xxd
  xz-utils
)

echo "Installing dependencies with apt-get ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y "${APT_PACKAGES[@]}"

version_ge() {
  dpkg --compare-versions "$1" ge "$2"
}

get_latest_yad_version() {
  local tag
  tag=$(curl -fsSL https://api.github.com/repos/v1cont/yad/releases/latest | \
        grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"\s*:\s*"([^\"]+)".*/\1/')
  if [[ -z $tag ]]; then
    echo "Unable to determine the latest Yad version" >&2
    exit 1
  fi
  printf '%s\n' "$tag"
}

normalize_yad_tag() {
  local version="$1"
  local tag
  if [[ "$version" == "latest" ]]; then
    tag=$(get_latest_yad_version)
  else
    tag="$version"
  fi
  [[ $tag != v* ]] && tag="v$tag"
  printf '%s\n' "$tag"
}

run_as_user() {
  local user="$1"
  shift
  local cmd=("$@")

  local tmp_script
  tmp_script=$(mktemp)

  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    if [[ -n $DISPLAY_ORIG ]]; then
      printf 'export DISPLAY=%q\n' "$DISPLAY_ORIG"
    fi
    if [[ -n $XAUTHORITY_ORIG ]]; then
      printf 'export XAUTHORITY=%q\n' "$XAUTHORITY_ORIG"
    fi
    printf 'export HOME=%q\n' "$CALLING_HOME"
    printf 'cd %q\n' "$CALLING_HOME"
    printf 'exec'
    for arg in "${cmd[@]}"; do
      printf ' %q' "$arg"
    done
    echo
  } >"$tmp_script"

  chmod 755 "$tmp_script"

  if [[ "$user" == "root" ]]; then
    bash "$tmp_script"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- bash "$tmp_script"
  else
    su - "$user" -c "bash $tmp_script"
  fi
  local status=$?
  rm -f "$tmp_script"
  return $status
}

YAD_INSTALLED_VERSION=""

install_yad_release() {
  local workdir="$1"
  local version_tag
  version_tag=$(normalize_yad_tag "$YAD_VERSION")
  local version_no_v="${version_tag#v}"
  local tarball="yad-${version_no_v}.tar.xz"
  local url="https://github.com/v1cont/yad/releases/download/${version_tag}/${tarball}"

  echo "Downloading Yad ${version_tag} ..."
  curl -fsSL "$url" -o "$workdir/$tarball"

  local src_dir="$workdir/yad-${version_no_v}"
  rm -rf "$src_dir"
  tar -xf "$workdir/$tarball" -C "$workdir"

  pushd "$src_dir" >/dev/null
  echo "Configuring Yad at $YAD_PREFIX ..."
  ./configure --prefix="$YAD_PREFIX" >/dev/null
  echo "Building Yad ..."
  make -j "$(nproc 2>/dev/null || echo 1)" >/dev/null
  echo "Installing Yad ..."
  make install >/dev/null
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q "$YAD_PREFIX/share/icons/hicolor" || true
  fi
  if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "$YAD_PREFIX/share/glib-2.0/schemas" || true
  fi
  popd >/dev/null

  export PATH="$YAD_PREFIX/bin:$PATH"
  YAD_INSTALLED_VERSION="$version_no_v"
}

remove_debian_yad() {
  if dpkg -s yad >/dev/null 2>&1; then
    echo "Removing system Yad package ..."
    apt-get purge -y yad || true
  fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

remove_debian_yad
install_yad_release "$WORKDIR"

if [[ "$YAD_PREFIX/bin/yad" != "/usr/local/bin/yad" ]]; then
  install -d /usr/local/bin
  ln -sf "$YAD_PREFIX/bin/yad" /usr/local/bin/yad
fi

if [[ "$YAD_PREFIX/bin/yad" != "/usr/bin/yad" ]]; then
  install -d /usr/bin
  ln -sf "$YAD_PREFIX/bin/yad" /usr/bin/yad
fi

if [[ -z $YAD_INSTALLED_VERSION ]]; then
  echo "Error: unable to determine the installed version of Yad" >&2
  exit 1
fi

if ! version_ge "$YAD_INSTALLED_VERSION" "$YAD_MIN_VERSION"; then
  echo "Error: Yad version ($YAD_INSTALLED_VERSION) lower than $YAD_MIN_VERSION" >&2
  exit 1
fi

echo "Yad $YAD_INSTALLED_VERSION installed in $YAD_PREFIX"

echo "Downloading SteamTinkerLaunch (branch: $BRANCH) ..."
git clone --depth=1 --branch "$BRANCH" https://github.com/sonic2kk/steamtinkerlaunch "$WORKDIR/steamtinkerlaunch"

pushd "$WORKDIR/steamtinkerlaunch" >/dev/null
make install PREFIX="$PREFIX" >/dev/null
popd >/dev/null

STL_BIN="$PREFIX/bin/steamtinkerlaunch"
if [[ -x "$STL_BIN" ]]; then
  if [[ "$CALLING_USER" == "root" ]]; then
    echo "Warning: run 'steamtinkerlaunch compat add' as a non-root user to complete registration."
  else
    run_as_user "$CALLING_USER" "$STL_BIN" --version || true
    run_as_user "$CALLING_USER" "$STL_BIN" compat add
  fi
fi

echo "SteamTinkerLaunch installed at $STL_BIN"
echo "Ready to use. Restart Steam to see the tool."

