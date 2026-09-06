#!/bin/bash
# mmpOS launcher for Quilibrium (ceremonyclient node).
#
# Runs the existing node installation in place — the binary (~226 MB) and the
# node's identity live on the rig and are never shipped in this package.
#
# Why a wrapper instead of the upstream release_autorun.sh:
#   * that script owns its own crash-restart loop, which fights mmpOS's watchdog;
#     here the node runs in the FOREGROUND and mmpOS restarts it if it dies
#   * it hardcodes GOMAXPROCS=16, which oversubscribes a rig already mining
#     something else — exposed as --gomaxprocs instead
#   * it had no autostart at all, so nothing came back after a reboot
#
# CRITICAL: mmpOS runs miners as ROOT, so $HOME is /root while the node lives under
# the interactive user (e.g. /home/miner/quill). Never trust $HOME here.

ORIGINAL_ARGS=("$@")
RMR=(-r -f)

# ----- package self-update ------------------------------------------------
PACKAGE_URL="https://github.com/Sebdev43/quilibrium-mmpos/releases/download/latest/quilibrium-latest_mmpos.tar.gz"
HASH_URL="${PACKAGE_URL}.sha256"
INSTALLED_HASH_FILE=".installed_hash"
UPDATE_LOCK_FILE=".update.lock"
MAX_UPDATE_DEPTH=1

try_self_update() {
    [[ -n "$SCRIPT_DIR" ]] || return 0
    if [[ "${MMP_UPDATE_DEPTH:-0}" -ge "$MAX_UPDATE_DEPTH" ]]; then return 0; fi
    for c in curl flock tar sha256sum; do command -v "$c" >/dev/null 2>&1 || return 0; done

    exec 200>"$SCRIPT_DIR/$UPDATE_LOCK_FILE" 2>/dev/null || return 0
    flock -n 200 || return 0

    local remote_hash
    remote_hash=$(curl -sfL --max-time 10 "$HASH_URL" 2>/dev/null | tr -d '[:space:]')
    [[ "$remote_hash" =~ ^[a-f0-9]{64}$ ]] || return 0

    local installed_hash=""
    [[ -f "$SCRIPT_DIR/$INSTALLED_HASH_FILE" ]] && \
        installed_hash=$(tr -d '[:space:]' < "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null)
    if [[ -z "$installed_hash" ]]; then
        echo "$remote_hash" > "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null; return 0
    fi
    [[ "$remote_hash" == "$installed_hash" ]] && return 0

    echo "[update] new package: $remote_hash"
    local tmpdir; tmpdir=$(mktemp -d 2>/dev/null) || return 0
    # shellcheck disable=SC2064
    trap "rm ${RMR[*]} '$tmpdir'" RETURN

    curl -sfL --max-time 120 --retry 2 -o "$tmpdir/pkg.tar.gz" "$PACKAGE_URL" || return 0
    [[ "$(sha256sum "$tmpdir/pkg.tar.gz" | awk '{print $1}')" == "$remote_hash" ]] || { echo "[update] hash mismatch"; return 0; }
    tar -tzf "$tmpdir/pkg.tar.gz" 2>/dev/null | grep -qE '(^/|(^|/)\.\./)' && { echo "[update] unsafe paths"; return 0; }

    mkdir -p "$tmpdir/staged"
    tar -xzf "$tmpdir/pkg.tar.gz" -C "$tmpdir/staged" --no-same-owner --no-same-permissions 2>/dev/null || return 0
    bash -n "$tmpdir/staged/start_mmpos.sh" 2>/dev/null || { echo "[update] new wrapper fails bash -n"; return 0; }

    local backup_dir="$SCRIPT_DIR/.backup_pre_update"
    rm "${RMR[@]}" "$backup_dir" 2>/dev/null; mkdir -p "$backup_dir" 2>/dev/null
    cp -af "$SCRIPT_DIR"/start_mmpos.sh "$SCRIPT_DIR"/mmp-stats.sh "$SCRIPT_DIR"/mmp-external.conf "$backup_dir"/ 2>/dev/null
    if ! cp -af "$tmpdir/staged/." "$SCRIPT_DIR/" 2>/dev/null || ! bash -n "$SCRIPT_DIR/start_mmpos.sh" 2>/dev/null; then
        echo "[update] apply failed, restoring backup"
        cp -af "$backup_dir"/. "$SCRIPT_DIR/" 2>/dev/null; return 0
    fi
    chmod +x "$SCRIPT_DIR/start_mmpos.sh" "$SCRIPT_DIR/mmp-stats.sh" 2>/dev/null
    echo "$remote_hash" > "$SCRIPT_DIR/$INSTALLED_HASH_FILE" 2>/dev/null
    echo "[update] applied, re-exec"
    flock -u 200 2>/dev/null
    export MMP_UPDATE_DEPTH=$((${MMP_UPDATE_DEPTH:-0} + 1))
    exec "$SCRIPT_DIR/start_mmpos.sh" "${ORIGINAL_ARGS[@]}"
}

# ----- arguments ----------------------------------------------------------
NODE_DIR=""           # empty => auto-detect
WORKER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --node-dir)       NODE_DIR="$2"; shift 2 ;;
        --worker|--rigid) WORKER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
try_self_update

# ----- locate the node installation (root-safe) ---------------------------
# mmpOS runs miners as ROOT, so $HOME is /root while the node lives under the
# interactive user. Probe the usual locations for a real release_autorun.sh.
if [[ -z "$NODE_DIR" ]]; then
    for cand in "$HOME/quill" /home/miner/quill /root/quill /home/*/quill \
                "$HOME/ceremonyclient/node" /home/*/ceremonyclient/node; do
        if [[ -f "$cand/release_autorun.sh" ]]; then NODE_DIR="$cand"; break; fi
    done
fi
[[ -f "$NODE_DIR/release_autorun.sh" ]] || {
    echo "ERROR: release_autorun.sh not found. Pass --node-dir <path>."; exit 1; }

cd "$NODE_DIR" || exit 1
chmod +x ./release_autorun.sh 2>/dev/null

echo "=========================================="
echo "  QUILIBRIUM - mmpOS   (release_autorun.sh)"
echo "  Dir:        $NODE_DIR"
echo "  Worker:     ${WORKER:-<none>}  (informational)"
echo "  Running as: $(id -un)"
echo "=========================================="

[[ -f "./.config/config.yml" ]] || echo "WARNING: no .config/config.yml here — the node may generate a new identity"

# release_autorun.sh backgrounds the node and loops, so on shutdown we must kill
# the node too: mmpOS kills the wrapper, not its grandchildren.
cleanup() {
    kill -TERM "$RPID" 2>/dev/null
    pkill -f 'node-.*-linux-' 2>/dev/null
}
trap cleanup SIGTERM SIGINT

# The node logs through stderr, but mmpOS only captures stdout — without this
# redirection its output lands in /dev/null and the miner looks silent.
./release_autorun.sh 2>&1 &
RPID=$!
wait "$RPID"
