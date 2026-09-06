# quilibrium-mmpos

Custom **mmpOS** miner package that runs an existing **Quilibrium** (ceremonyclient)
node via its own `release_autorun.sh`, so the node starts automatically with the rig and
is supervised like any other miner — including alongside a second miner on the host.

## What it does

`release_autorun.sh` works fine, but nothing ever launches it: there is no autostart, so
after a reboot the node simply stays down. This wrapper is the missing piece.

- **Locates the node installation without trusting `$HOME`.** mmpOS runs miners as
  **root**, while the node normally lives under the interactive user
  (`/home/miner/quill`, `~/ceremonyclient/node`, …). It probes those locations for a real
  `release_autorun.sh`.
- **Runs `release_autorun.sh` unmodified**, from the node's own directory (it reads
  `.config/` relatively).
- **Kills the node on shutdown.** `release_autorun.sh` backgrounds the node binary, so
  stopping the wrapper alone would leave an orphan; the wrapper terminates it explicitly.
- **Self-updates** from this repository's `latest` release.

The node binary (~226 MB) and the node's identity (`.config/`, `keys.yml`) stay on the
rig. **Nothing from the node installation is contained in this repository or its releases.**

## Usage

| Field | Value |
|---|---|
| Miner | `custom` |
| Miner version | `latest` |
| Custom miner URL | `https://github.com/Sebdev43/quilibrium-mmpos/releases/download/latest/quilibrium-latest_mmpos.tar.gz?v=YYYYMMDD` |
| Command line | `./start_mmpos.sh --worker %rig_name%%miner_id%` |
| Platforms | `cpu_intel`, `cpu_amd` |
| API port | `0` |

**Options**

| Option | Default | Role |
|---|---|---|
| `--node-dir` | auto-detected | directory holding `release_autorun.sh` and `.config/` |
| `--worker` | — | informational |

## Running beside another miner

mmpOS supports several miners per rig (`%miner_id%`), so this can run in parallel with a
hashrate miner. Quilibrium is a background node and is light on CPU, so no explicit CPU
budgeting is applied here — `release_autorun.sh` keeps its own settings.

## Notes

- Quilibrium is a network node, not a hashrate miner: `mmp-stats.sh` reports `0 H/s` and
  uses the highest observed frame number as a liveness counter rather than inventing a
  hashrate.
- `release_autorun.sh` fetches new upstream releases on its own schedule; the wrapper does
  not interfere with that.

## License

MIT
