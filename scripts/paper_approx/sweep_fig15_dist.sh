#!/usr/bin/env bash
# Fig.15d/e on OSM (file) keys via data_server/data_client (USE_NN=0 / LR).
# Paper uses ~1e8 OSM keys; default here is 1e6 from osm_uni_10m.txt (32GiB HP).
# Optional: FIG15_DIST_NKEYS=10000000 for full 10M file (train time grows a lot).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -a; source "${SCRIPT_DIR}/config.env"; set +a

OUT_DIR="${SCRIPT_DIR}/out"
mkdir -p "${OUT_DIR}"
CSV="${OUT_DIR}/fig15_dist_data.csv"
echo "nmodels,keys_per_model,peak_thpt_rps,peak_lat_us,low_thpt_rps,low_lat_us,n_ok_peak,n_ok_low,nkeys,data_file" >"${CSV}"

NKEYS=${FIG15_DIST_NKEYS:-${NKEYS}}
DATA_FILE=${FIG15_DIST_DATA_FILE:-${DATA_FILE}}
export NKEYS DATA_FILE

kill_server() {
  for p in $(pgrep -x data_server || true); do kill -9 "$p" 2>/dev/null || true; done
  sleep 2
}

start_server() {
  local nmodels=$1
  local log="${OUT_DIR}/fig15_dist_server_${nmodels}.log"
  kill_server
  : >"${log}"
  cd "${XSTORE_ROOT}"
  if [[ ! -f "${DATA_FILE}" ]]; then
    echo "error: DATA_FILE=${DATA_FILE} missing under ${XSTORE_ROOT}" >&2
    return 1
  fi
  export MKL_THREADING_LAYER=SEQUENTIAL
  export LD_LIBRARY_PATH="${XSTORE_ROOT}/deps/boost/lib:${XSTORE_ROOT}/deps/mkl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  nohup ./data_server \
    --port="${SERVER_PORT}" --threads="${SERVER_THREADS}" \
    --alloc_mem_m="${SERVER_ALLOC_MEM_M}" --use_nic_idx="${SERVER_NIC_IDX}" \
    --len="${VAL_LEN}" --nkeys="${NKEYS}" --nmodels="${nmodels}" \
    --ncheck_model=0 --vlen=false \
    --data_file="${DATA_FILE}" \
    --server_life_s="${SERVER_LIFE_S}" \
    >"${log}" 2>&1 &
  echo "waiting for index (nmodels=${nmodels} nkeys=${NKEYS} file=${DATA_FILE})..."
  # OSM train can be slow; allow up to ~1h for large nmodels.
  for _ in $(seq 1 1800); do
    if grep -q 'index related work done!' "${log}" 2>/dev/null; then
      return 0
    fi
    if ! pgrep -x data_server >/dev/null; then
      echo "server died; see ${log}" >&2
      tail -40 "${log}" >&2 || true
      return 1
    fi
    sleep 2
  done
  echo "timeout waiting for server" >&2
  return 1
}

run_load() {
  local spec=$1 name_base=$2 out=$3
  local T C N remote_log
  IFS=':' read -r T C N <<<"${spec}"
  remote_log="${out}.ssh.log"
  if ! ssh "${CLIENT_HOST}" "rm -rf '${out}'; mkdir -p '${out}'; set -a; source '${SCRIPT_DIR}/config.env'; set +a; \
    export CLIENT_NAME_BASE=${name_base} THREADS_PER_CLIENT=${T} COROS=${C} NKEYS=${NKEYS} DATA_FILE=${DATA_FILE}; \
    '${SCRIPT_DIR}/run_data_clients.sh' ${N} '${out}'" >"${remote_log}" 2>&1; then
    echo "warning: run_data_clients failed for ${spec}; see ${remote_log}" >&2
    return 1
  fi
  if ! ssh "${CLIENT_HOST}" "compgen -G '${out}/*.xstorelog'" >/dev/null 2>&1; then
    echo "warning: no logs for load ${spec}; see ${remote_log}" >&2
    return 1
  fi
  rm -rf "${out}"
  mkdir -p "${out}"
  rsync -a --delete "${CLIENT_HOST}:${out}/" "${out}/" >/dev/null 2>&1
  python3 "${SCRIPT_DIR}/aggregate_thpt.py" \
    --dir "${out}" --trim-head "${TRIM_HEAD}" --trim-tail "${TRIM_TAIL}" \
    --expect "${N}" --csv-row "${spec}"
}

NAME_BASE=5000
IFS=',' read -r -a MS <<<"${FIG15_DIST_NMODELS_LIST:-${FIG15_NMODELS_LIST}}"
for m in "${MS[@]}"; do
  m=$(echo "${m}" | tr -d '[:space:]')
  [[ -z "${m}" ]] && continue
  kpm=$(python3 -c "print(${NKEYS}/${m})")
  echo "======== Fig.15-dist OSM nmodels=${m} nkeys=${NKEYS} (keys/model≈${kpm}) ========"
  start_server "${m}" || continue

  peak_agg=nan; peak_lat=nan; peak_nok=0
  low_agg=nan; low_lat=nan; low_nok=0

  echo "  peak load ${FIG15_PEAK_LOAD}..."
  if peak_line=$(run_load "${FIG15_PEAK_LOAD}" "${NAME_BASE}" "${OUT_DIR}/fig15_dist_m${m}_peak"); then
    IFS=',' read -r _p peak_agg _pavg peak_nok _pexp peak_lat <<<"${peak_line}"
    echo "  peak → thpt=${peak_agg} lat=${peak_lat} n_ok=${peak_nok}"
  else
    echo "  peak FAILED" >&2
  fi
  NAME_BASE=$((NAME_BASE + 40))

  echo "  low load ${FIG15_LOW_LOAD}..."
  if low_line=$(run_load "${FIG15_LOW_LOAD}" "${NAME_BASE}" "${OUT_DIR}/fig15_dist_m${m}_low"); then
    IFS=',' read -r _l low_agg _lavg low_nok _lexp low_lat <<<"${low_line}"
    echo "  low → thpt=${low_agg} lat=${low_lat} n_ok=${low_nok}"
  else
    echo "  low FAILED" >&2
  fi
  NAME_BASE=$((NAME_BASE + 40))

  echo "${m},${kpm},${peak_agg},${peak_lat},${low_agg},${low_lat},${peak_nok},${low_nok},${NKEYS},${DATA_FILE}" | tee -a "${CSV}"

  kill_server
  rm -rf "${OUT_DIR}/fig15_dist_m${m}_peak" "${OUT_DIR}/fig15_dist_m${m}_low"
  rm -f "${OUT_DIR}/fig15_dist_server_${m}.log" \
        "${OUT_DIR}/fig15_dist_m${m}_peak.ssh.log" "${OUT_DIR}/fig15_dist_m${m}_low.ssh.log"
done

python3 "${SCRIPT_DIR}/plot_paper.py" --data-dir "${OUT_DIR}" --fig15-dist
echo "Fig.15-dist done → ${OUT_DIR}/fig15d_dist_*.* ${OUT_DIR}/fig15e_dist_*.*"
