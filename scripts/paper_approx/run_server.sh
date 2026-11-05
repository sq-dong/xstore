#!/usr/bin/env bash
# Run on memserver16. Keep alive for the whole client sweep.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
set -a; source "${SCRIPT_DIR}/config.env"; set +a

cd "${XSTORE_ROOT}"
exec ./ycsb_server \
  --port="${SERVER_PORT}" \
  --threads="${SERVER_THREADS}" \
  --alloc_mem_m="${SERVER_ALLOC_MEM_M}" \
  --use_nic_idx="${SERVER_NIC_IDX}" \
  --len="${VAL_LEN}" \
  --nkeys="${NKEYS}" \
  --nmodels="${NMODELS}" \
  --ncheck_model=0 \
  --vlen="${VLEN}" \
  --load_from_file="${LOAD_FROM_FILE}" \
  --server_life_s="${SERVER_LIFE_S}"
