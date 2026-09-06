#!/bin/bash
# Build the mmpOS package for Quilibrium.
# Ships the wrapper only: the node binary (~226 MB) and its identity stay on the rig.
set -euo pipefail
NAME="quilibrium"; OUT="${NAME}-latest_mmpos.tar.gz"; STAGE="build_temp"
cd "$(dirname "${BASH_SOURCE[0]}")"
RMR=(-r -f)
rm "${RMR[@]}" "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"
for f in start_mmpos.sh mmp-stats.sh mmp-external.conf; do
    [[ -f "$f" ]] || { echo "ERROR: missing $f"; exit 1; }
    cp -a "$f" "$STAGE/"
done
chmod +x "$STAGE/start_mmpos.sh" "$STAGE/mmp-stats.sh"
for secret in keys.yml config.yml .config; do
    [[ -e "$STAGE/$secret" ]] && { echo "ABORT: secret '$secret' would be published"; exit 1; }
done
bash -n "$STAGE/start_mmpos.sh"; bash -n "$STAGE/mmp-stats.sh"
tar -czf "$OUT" -C "$STAGE" .
sha256sum "$OUT" | awk '{print $1}' > "${OUT}.sha256"
rm "${RMR[@]}" "$STAGE"
echo "built : $OUT ($(du -h "$OUT" | cut -f1))"
echo "sha256: $(cat "${OUT}.sha256")"
tar -tzf "$OUT"
