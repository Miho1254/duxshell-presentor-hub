#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Run only after the user explicitly requests a build in the widget.
set -eu

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
project_dir=$(dirname -- "$plugin_dir")
if [ ! -f "$project_dir/CMakeLists.txt" ] || [ ! -f "$project_dir/core/main.cpp" ]; then
    printf '%s\n' 'Source files are unavailable. Reinstall Presentation Hub from its repository.' >&2
    exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
    printf '%s\n' 'CMake is missing. Install CMake, a C++17 compiler and Qt 6 development packages.' >&2
    exit 1
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/presentation-hub-build.XXXXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT
trap 'exit 1' HUP INT TERM
cmake -S "$project_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build "$build_dir" --parallel
if [ ! -x "$plugin_dir/bin/presentation-hub-core" ]; then
    printf '%s\n' 'The core build completed without an executable.' >&2
    exit 1
fi
printf '%s\n' 'Presentation Hub core is ready.'
