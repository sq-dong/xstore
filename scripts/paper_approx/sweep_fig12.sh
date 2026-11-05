#!/usr/bin/env bash
# Fig.12a: sweep offered load (T:C:N) → (aggregate thpt, median latency).
# Run on bfhost_72 while ycsb_server is up on memserver16.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set -a; source "${SCRIPT_DIR}/config.env"; set +a

OUT_DIR="${SCRIPT_DIR}/out"
mkdir -p "${OUT_DIR}"
CSV="${OUT_DIR}/fig12_data.csv"
echo "load_id,threads,coros,nclients,agg_thpt_rps,per_client_avg_rps,n_ok,n_expect,lat_us_median" >"${CSV}"

NAME_BASE=100
IFS=',' read -r -a LOADS <<<"${FIG12_LOAD_LIST}"
for spec in "${LOADS[@]}"; do
  spec=$(echo "${spec}" | tr -d '[:space:]')
  [[ -z "${spec}" ]] && continue
  IFS=':' read -r T C N <<<"${spec}"
  echo "======== Fig.12 load T=${T} C=${C} N=${N} ========"
  export THREADS_PER_CLIENT="${T}" COROS="${C}" CLIENT_NAME_BASE="${NAME_BASE}"
  out="${OUT_DIR}/fig12_t${T}_c${C}_n${N}"
  rm -rf "${out}"
  if ! "${SCRIPT_DIR}/run_clients.sh" "${N}" "${out}"; then
    echo "warning: run_clients failed for ${spec}" >&2
    NAME_BASE=$((NAME_BASE + N + 20))
    continue
  fi
  if ! compgen -G "${out}/*.xstorelog" >/dev/null; then
    echo "warning: no logs for ${spec}" >&2
    NAME_BASE=$((NAME_BASE + N + 20))
    continue
  fi
  line=$(python3 "${SCRIPT_DIR}/aggregate_thpt.py" \
    --dir "${out}" --trim-head "${TRIM_HEAD}" --trim-tail "${TRIM_TAIL}" \
    --expect "${N}" --csv-row "${spec}")
  # csv-row,agg,avg,nok,nexp,lat → prepend T,C,N
  IFS=',' read -r _id agg avg nok nexp lat <<<"${line}"
  echo "${spec},${T},${C},${N},${agg},${avg},${nok},${nexp},${lat}" | tee -a "${CSV}"
  NAME_BASE=$((NAME_BASE + N + 20))
  sleep 3
done

python3 "${SCRIPT_DIR}/plot_paper.py" --data-dir "${OUT_DIR}"
echo "Fig.12a done → ${OUT_DIR}/fig12a_thpt_latency.*"
