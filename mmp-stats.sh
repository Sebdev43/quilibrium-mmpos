#!/usr/bin/env bash
# mmpOS stats adapter for Quilibrium.
# mmpOS calls:  mmp-stats.sh <device_num> <log_file>
#
# Quilibrium is a network node, not a hashrate miner, and it writes nothing to stdout,
# so there is no log to parse and no H/s to report. The only real liveness signal is the
# node's own `--node-info`, which prints "Frame Number: N".
#
# That binary is ~226 MB and reloads the keystore on every call, so the result is CACHED:
# it is refreshed at most every CACHE_TTL seconds and served from disk in between.
#
# Reported as: hash = 0 (honest — there is no hashrate), accepted = frame number.

DEVICE_NUM=$1
LOG_FILE=$2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$SCRIPT_DIR/.frame_cache"
CACHE_TTL=300

MINER_NAME="quilibrium"
MINER_VERSION="latest"

emit() {
    jq -n \
        --argjson hash 0 \
        --argjson acc "${1:-0}" \
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

# Serve from cache when it is fresh enough.
if [[ -f "$CACHE" ]]; then
    read -r ts frame ver < "$CACHE" 2>/dev/null
    now=$(date +%s)
    if [[ -n "$ts" ]] && (( now - ts < CACHE_TTL )); then
        [[ -n "$ver" ]] && MINER_VERSION="$ver"
        emit "${frame:-0}"
        exit 0
    fi
fi

# Cache miss: locate the node (root-safe, same probe as the launcher) and ask it.
NODE_DIR=""
for cand in "$HOME/quill" /home/miner/quill /root/quill /home/*/quill \
            "$HOME/ceremonyclient/node" /home/*/ceremonyclient/node; do
    [[ -f "$cand/release_autorun.sh" ]] && { NODE_DIR="$cand"; break; }
done

if [[ -z "$NODE_DIR" ]]; then emit 0; exit 0; fi
cd "$NODE_DIR" || { emit 0; exit 0; }

ARCH=$([[ "$(uname -m)" == aarch64* ]] && echo arm64 || echo amd64)
NODE_BIN=$(ls -1 node-*-linux-"$ARCH" 2>/dev/null | grep -vE '\.(dgst|sig|part)' | sort -V | tail -1)
if [[ -z "$NODE_BIN" ]]; then emit 0; exit 0; fi

info=$(timeout 90 "./$NODE_BIN" --node-info 2>/dev/null)
frame=$(echo "$info" | grep -oE 'Frame Number: [0-9]+' | grep -oE '[0-9]+' | tail -1)
ver=$(echo "$info"   | grep -oE 'Version: [0-9.]+'   | awk '{print $2}' | tail -1)
[[ -n "$ver" ]] && MINER_VERSION="$ver"

if [[ -n "$frame" ]]; then
    echo "$(date +%s) $frame $MINER_VERSION" > "$CACHE" 2>/dev/null
    emit "$frame"
else
    # Node busy or starting: keep the last known frame rather than reporting a regression.
    if [[ -f "$CACHE" ]]; then read -r _ old _ < "$CACHE"; emit "${old:-0}"; else emit 0; fi
fi
