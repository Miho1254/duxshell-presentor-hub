#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Build and install a standalone copy of the plugin without changing an existing install.
set -eu

if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' 'Run this installer as your normal user, not with sudo.' >&2
    exit 1
fi

for command in cmake mktemp grep; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
    fi
done

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
case $config_home in
    /*) ;;
    *) printf '%s\n' 'XDG_CONFIG_HOME must be an absolute path.' >&2; exit 1 ;;
esac
plugins_dir=$config_home/dms/plugins
destination=$plugins_dir/presentation-hub

if [ -e "$destination" ] || [ -L "$destination" ]; then
    printf 'An existing plugin is already at %s\n' "$destination" >&2
    printf '%s\n' 'Inspect it before replacing it; this installer never overwrites an installation.' >&2
    exit 1
fi

# DMS identifies plugins by manifest ID, not directory name.
for manifest in "$plugins_dir"/*/plugin.json; do
    [ -f "$manifest" ] || continue
    if grep -Eq '"id"[[:space:]]*:[[:space:]]*"presentationHub"' "$manifest"; then
        printf 'Presentation Hub is already registered at %s\n' "${manifest%/plugin.json}" >&2
        exit 1
    fi
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/presentation-hub-install.XXXXXXXX")
staging_dir=
cleanup() {
    if [ -n "$staging_dir" ] && [ -d "$staging_dir" ]; then
        rm -rf -- "$staging_dir"
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$work_dir/source/core" "$work_dir/source/presentation-hub"
cp "$project_dir/CMakeLists.txt" "$work_dir/source/"
cp "$project_dir/core/main.cpp" "$project_dir/core/presentation_rules.h" "$work_dir/source/core/"
cp "$project_dir/presentation-hub/"*.qml "$project_dir/presentation-hub/plugin.json" "$work_dir/source/presentation-hub/"

printf '%s\n' 'Building Presentation Hub core...'
cmake -S "$work_dir/source" -B "$work_dir/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build "$work_dir/build" --parallel

mkdir -p "$plugins_dir"
staging_dir=$(mktemp -d "$plugins_dir/.presentation-hub-install.XXXXXXXX")
cp -R "$work_dir/source/presentation-hub/." "$staging_dir/"
# The staged directory is on the same filesystem; never replace an existing path.
mv -nT -- "$staging_dir" "$destination"
if [ -e "$staging_dir" ]; then
    printf 'Installation was not changed: %s already exists.\n' "$destination" >&2
    exit 1
fi
staging_dir=

printf '\nInstalled Presentation Hub at %s\n' "$destination"
printf '%s\n' 'Open DMS Settings → Plugins, scan for plugins if needed, enable Presentation Hub, and add its widget to the bar.'
if ! command -v wl-mirror >/dev/null 2>&1; then
    printf '%s\n' 'Optional: install wl-mirror with your package manager to enable Duplicate. Other features do not require it.'
fi
