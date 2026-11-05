# Paper-approx sweeps (OSDI'20 axes)

Scripts that reproduce axis-aligned versions of Fig.12a / 15d-e / 16a for
XStore only (no comparison systems). Edit `config.env`, then:

| Script | Where | Notes |
|--------|-------|-------|
| `run_server.sh` | server host | default `ycsb_server` for Fig.12 |
| `sweep_fig12.sh` | client host | server must already be up |
| `sweep_fig15.sh` / `sweep_fig16.sh` | server host | restarts `ycsb_server`; SSHs clients |
| `sweep_fig15_dist.sh` | server host | OSM keys via `data_server` / `data_client` |
| `plot_paper.py` | either | plots CSVs under `out/`; use `--fig15-dist` for OSM |

Sync binaries, this directory, and (for OSM) the key file to the client host
before sweeping. Both hosts need HugePages and:

```bash
export LD_LIBRARY_PATH=$XSTORE_ROOT/deps/boost/lib:$XSTORE_ROOT/deps/mkl/lib
export MKL_THREADING_LAYER=SEQUENTIAL
```

`XSTORE_ROOT` defaults to the repo root when `config.env` is sourced.
Override `SERVER_HOST_IB`, `CLIENT_HOST`, and related knobs in `config.env`.
