#!/usr/bin/env bash
# Run on memserver16. data_server always loads USE_LOG keys from --data_file.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
set -a; source "${SCRIPT_DIR}/config.env"; set +a

cd "${XSTORE_ROOT}"
exec ./data_server \
  --port="${SERVER_PORT}" \
  --threads="${SERVER_THREADS}" \
  --alloc_mem_m="${SERVER_ALLOC_MEM_M}" \
  --use_nic_idx="${SERVER_NIC_IDX}" \
  --len="${VAL_LEN}" \
  --nkeys="${NKEYS}" \
  --nmodels="${NMODELS}" \
  --ncheck_model=0 \
  --vlen=false \
  --data_file="${DATA_FILE}" \
  --server_life_s="${SERVER_LIFE_S}"
