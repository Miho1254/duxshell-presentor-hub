#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
core=${1:-./presentation-hub/bin/presentation-hub-core}
"$core" snapshot | jq -e '.outputs | type == "array"' >/dev/null
if "$core" move --window 0 --output missing >/dev/null 2>&1; then
    echo 'Invalid window ID was accepted' >&2
    exit 1
fi
if NIRI_SOCKET= "$core" snapshot >/dev/null 2>&1; then
    echo 'Missing NIRI_SOCKET was accepted' >&2
    exit 1
fi
printf '%s\n' 'Core smoke checks passed.'
