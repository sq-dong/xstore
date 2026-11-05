#!/usr/bin/env bash
# Fig.16a: peak thpt vs value size for inline (vlen=false) and indirect (vlen=true).
# Uses FIG16_LOAD (T:C:N), same peak-pressure idea as Fig.12/15.
# Run on memserver16 (restarts server per (len,vlen); clients on CLIENT_HOST).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -a; source "${SCRIPT_DIR}/config.env"; set +a

OUT_DIR="${SCRIPT_DIR}/out"
mkdir -p "${OUT_DIR}"
CSV="${OUT_DIR}/fig16_data.csv"
echo "len,vlen,agg_thpt_rps,per_client_avg_rps,n_ok,n_expect,lat_us_median" >"${CSV}"

kill_server() {
  for p in $(pgrep -x ycsb_server || true); do kill -9 "$p" 2>/dev/null || true; done
  sleep 2
}

start_server() {
  local len=$1 vlen=$2
  local log="${OUT_DIR}/fig16_server_l${len}_v${vlen}.log"
  kill_server
  : >"${log}"
  cd "${XSTORE_ROOT}"
  export MKL_THREADING_LAYER=SEQUENTIAL
  export LD_LIBRARY_PATH="${XSTORE_ROOT}/deps/boost/lib:${XSTORE_ROOT}/deps/mkl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  # Prefer global SERVER_ALLOC_MEM_M (16GiB+ after HP bump); bump further for large vlen arenas.
  local alloc=${SERVER_ALLOC_MEM_M}
  if [[ "${vlen}" == "true" && "${len}" -ge 512 && "${alloc}" -lt 24576 ]]; then
    alloc=24576
  fi
  nohup ./ycsb_server \
    --port="${SERVER_PORT}" --threads="${SERVER_THREADS}" \
    --alloc_mem_m="${alloc}" --use_nic_idx="${SERVER_NIC_IDX}" \
    --len="${len}" --nkeys="${NKEYS}" --nmodels="${NMODELS}" \
    --ncheck_model=0 --vlen="${vlen}" --load_from_file=false \
    --server_life_s="${SERVER_LIFE_S}" \
    >"${log}" 2>&1 &
  echo "waiting for index (len=${len} vlen=${vlen} alloc=${alloc})..."
  for _ in $(seq 1 180); do
    if grep -q 'index related work done!' "${log}" 2>/dev/null; then
      return 0
    fi
    if ! pgrep -x ycsb_server >/dev/null; then
      echo "server died; see ${log}" >&2
      return 1
    fi
    sleep 2
  done
  echo "timeout waiting for server" >&2
  return 1
}

run_load() {
  local spec=$1 name_base=$2 out=$3 len=$4 vlen=$5
  local T C N remote_log
  IFS=':' read -r T C N <<<"${spec}"
  remote_log="${out}.ssh.log"
  if ! ssh "${CLIENT_HOST}" "rm -rf '${out}'; mkdir -p '${out}'; set -a; source '${SCRIPT_DIR}/config.env'; set +a; \
    export VAL_LEN=${len} VLEN=${vlen} \
      CLIENT_NAME_BASE=${name_base} THREADS_PER_CLIENT=${T} COROS=${C}; \
    '${SCRIPT_DIR}/run_clients.sh' ${N} '${out}'" >"${remote_log}" 2>&1; then
    echo "warning: run_clients failed for ${spec}; see ${remote_log}" >&2
    return 1
  fi
  if ! ssh "${CLIENT_HOST}" "compgen -G '${out}/*.xstorelog'" >/dev/null 2>&1; then
    echo "warning: no logs for ${spec}; see ${remote_log}" >&2
    return 1
  fi
  rm -rf "${out}"
  mkdir -p "${out}"
  rsync -a --delete "${CLIENT_HOST}:${out}/" "${out}/" >/dev/null 2>&1
  python3 "${SCRIPT_DIR}/aggregate_thpt.py" \
    --dir "${out}" --trim-head "${TRIM_HEAD}" --trim-tail "${TRIM_TAIL}" \
    --expect "${N}" --csv-row "${len}"
}

NAME_BASE=5000
IFS=':' read -r _FT _FC FIG16_N <<<"${FIG16_LOAD}"
IFS=',' read -r -a LENS <<<"${FIG16_LEN_LIST}"
for len in "${LENS[@]}"; do
  len=$(echo "${len}" | tr -d '[:space:]')
  [[ -z "${len}" ]] && continue
  for vlen in false true; do
    echo "======== Fig.16 len=${len} vlen=${vlen} load=${FIG16_LOAD} ========"
    start_server "${len}" "${vlen}" || continue
    out="${OUT_DIR}/fig16_l${len}_v${vlen}"
    if line=$(run_load "${FIG16_LOAD}" "${NAME_BASE}" "${out}" "${len}" "${vlen}"); then
      IFS=',' read -r _l agg avg nok nexp lat <<<"${line}"
      echo "${len},${vlen},${agg},${avg},${nok},${nexp},${lat}" | tee -a "${CSV}"
      echo "  → thpt=${agg} lat=${lat} n_ok=${nok}"
    else
      echo "warning: no data for len=${len} vlen=${vlen}" >&2
    fi
    NAME_BASE=$((NAME_BASE + FIG16_N + 30))
    kill_server
    rm -rf "${out}"
    rm -f "${OUT_DIR}/fig16_server_l${len}_v${vlen}.log" "${out}.ssh.log"
  done
done

python3 "${SCRIPT_DIR}/plot_paper.py" --data-dir "${OUT_DIR}"
echo "Fig.16a done → ${OUT_DIR}/fig16a_thpt_vs_vlen.*"
