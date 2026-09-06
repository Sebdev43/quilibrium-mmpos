#!/usr/bin/env bash
# mmpOS stats adapter for Quilibrium.
# mmpOS calls:  mmp-stats.sh <device_num> <log_file>
#
# Quilibrium is NOT a hashrate miner: it is a network node, so there is no H/s to
# report. We emit a valid, well-formed payload with hash 0 so the dashboard shows
# the miner as alive without inventing a number.
#
# TODO: once the node has produced logs on a rig, calibrate a real progress metric
# (frame number / proof count) here — do not guess it from documentation.

DEVICE_NUM=$1
LOG_FILE=$2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MINER_NAME="quilibrium"
MINER_VERSION="latest"
[[ -f "$SCRIPT_DIR/.quil_version" ]] && MINER_VERSION=$(tr -d '[:space:]' < "$SCRIPT_DIR/.quil_version")
[[ -z "$MINER_VERSION" ]] && MINER_VERSION="latest"

emit() {
    jq -n \
        --argjson hash "${1:-0}" \
        --argjson acc "${2:-0}" \
        --arg name "$MINER_NAME" \
        --arg ver "$MINER_VERSION" \
        '{
            busid: ["cpu"],
            hash:  [$hash],
            units: "hs",
            air:   [($acc|tostring), "0", "0"],
            miner_name: $name,
            miner_version: $ver
        }'
}

[[ -f "$LOG_FILE" ]] || { emit 0 0; exit 0; }

# Highest frame number seen, used as a liveness/progress counter in "accepted".
frame=$(grep -aoE '"frame_number":[0-9]+' "$LOG_FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
emit 0 "${frame:-0}"
