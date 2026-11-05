#!/usr/bin/env bash
# Run on bfhost_72 against data_server (OSM / file-key path).
# Usage: ./run_data_clients.sh <nclients> [out_dir]
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_SAVE_VAL_LEN=${VAL_LEN-}
_SAVE_NKEYS=${NKEYS-}
_SAVE_NMODELS=${NMODELS-}
_SAVE_THREADS=${THREADS_PER_CLIENT-}
_SAVE_COROS=${COROS-}
_SAVE_NAME_BASE=${CLIENT_NAME_BASE-}
_SAVE_DATA_FILE=${DATA_FILE-}
# shellcheck disable=SC1091
set -a; source "${SCRIPT_DIR}/config.env"; set +a
[[ -n "${_SAVE_VAL_LEN}" ]] && VAL_LEN="${_SAVE_VAL_LEN}"
[[ -n "${_SAVE_NKEYS}" ]] && NKEYS="${_SAVE_NKEYS}"
[[ -n "${_SAVE_NMODELS}" ]] && NMODELS="${_SAVE_NMODELS}"
[[ -n "${_SAVE_THREADS}" ]] && THREADS_PER_CLIENT="${_SAVE_THREADS}"
[[ -n "${_SAVE_COROS}" ]] && COROS="${_SAVE_COROS}"
[[ -n "${_SAVE_NAME_BASE}" ]] && CLIENT_NAME_BASE="${_SAVE_NAME_BASE}"
[[ -n "${_SAVE_DATA_FILE}" ]] && DATA_FILE="${_SAVE_DATA_FILE}"

NCLIENTS=${1:?usage: $0 <nclients> [out_dir]}
OUT_DIR=${2:-"${SCRIPT_DIR}/out/data_nclients_${NCLIENTS}"}
mkdir -p "${OUT_DIR}"
echo "data_client params: nkeys=${NKEYS} data_file=${DATA_FILE} T=${THREADS_PER_CLIENT} C=${COROS}"

if [[ "${THREADS_PER_CLIENT}" -gt 12 ]]; then
  echo "error: THREADS_PER_CLIENT=${THREADS_PER_CLIENT} > 12 (mlx5_1 DOWN)" >&2
  exit 1
fi

NPROC=$(nproc)
NEED_CPU=$((CPU_BASE + (NCLIENTS - 1) * CPU_STRIDE + THREADS_PER_CLIENT - 1))
if [[ "${NEED_CPU}" -ge "${NPROC}" ]]; then
  echo "error: need CPU up to ${NEED_CPU}, but nproc=${NPROC}" >&2
  exit 1
fi

HP_MIB_PER=$((512 + (THREADS_PER_CLIENT - 1) * 128))
HP_NEED_MIB=$((HP_MIB_PER * NCLIENTS))
HP_FREE_MIB=$(awk '/HugePages_Free/ {print $2}' /proc/meminfo)
HP_SIZE_MIB=$(awk '/Hugepagesize/ {print $2/1024}' /proc/meminfo)
HP_FREE_TOTAL_MIB=$(awk -v f="${HP_FREE_MIB}" -v s="${HP_SIZE_MIB}" 'BEGIN{printf "%d", f*s}')
if [[ "${HP_NEED_MIB}" -gt "${HP_FREE_TOTAL_MIB}" ]]; then
  echo "error: need ~${HP_NEED_MIB} MiB HugePages, free ~${HP_FREE_TOTAL_MIB} MiB" >&2
  exit 1
fi

cd "${XSTORE_ROOT}"
export MKL_THREADING_LAYER=SEQUENTIAL
export LD_LIBRARY_PATH="${XSTORE_ROOT}/deps/boost/lib:${XSTORE_ROOT}/deps/mkl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [[ ! -f "${DATA_FILE}" ]]; then
  echo "error: DATA_FILE missing at ${XSTORE_ROOT}/${DATA_FILE}" >&2
  exit 1
fi

rm -f ./*.xstorelog
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

ADDR="${SERVER_HOST_IB}:${SERVER_PORT}"
NAME_BASE=${CLIENT_NAME_BASE:-0}
echo "launching ${NCLIENTS} data_clients -> ${ADDR}; name_base=${NAME_BASE}; logs -> ${OUT_DIR}"

declare -a NAMES=()
for ((i = 1; i <= NCLIENTS; i++)); do
  name=$((NAME_BASE + i))
  NAMES+=("${name}")
  cpu_start=$((CPU_BASE + (i - 1) * CPU_STRIDE))
  if [[ "${THREADS_PER_CLIENT}" -eq 1 ]]; then
    cpu_list="${cpu_start}"
  else
    cpu_end=$((cpu_start + THREADS_PER_CLIENT - 1))
    cpu_list="${cpu_start}-${cpu_end}"
  fi
  log="${OUT_DIR}/client_${name}.log"
  stdbuf -oL -eL taskset -c "${cpu_list}" ./data_client \
    --addr="${ADDR}" \
    --threads="${THREADS_PER_CLIENT}" \
    --coros="${COROS}" \
    --nkeys="${NKEYS}" \
    --len="${VAL_LEN}" \
    --vlen=false \
    --data_file="${DATA_FILE}" \
    --client_name="${name}" \
    >"${log}" 2>&1 &
  echo $! >>"${OUT_DIR}/pids.txt"
  echo "  client_name=${name} pid=$! cpus=${cpu_list}"
  sleep "${CLIENT_STAGGER_S:-0.2}"
done

DEADLINE=$((SECONDS + CLIENT_WARMUP_S + REPORT_EPOCHS + CLIENT_EXTRA_WAIT_S + 120))
echo "waiting for ${NCLIENTS} non-empty xstorelog files..."
while (( SECONDS < DEADLINE )); do
  nlogs=0
  for name in "${NAMES[@]}"; do
    if [[ -f "${name}.xstorelog" && -s "${name}.xstorelog" ]]; then
      nlogs=$((nlogs + 1))
    fi
  done
  alive=0
  if [[ -f "${OUT_DIR}/pids.txt" ]]; then
    while read -r pid; do
      kill -0 "${pid}" 2>/dev/null && alive=$((alive + 1)) || true
    done <"${OUT_DIR}/pids.txt"
  fi
  if [[ "${nlogs}" -ge "${NCLIENTS}" && "${alive}" -eq 0 ]]; then
    break
  fi
  if [[ "${nlogs}" -ge "${NCLIENTS}" ]]; then
    sleep 3
    alive=0
    if [[ -f "${OUT_DIR}/pids.txt" ]]; then
      while read -r pid; do
        kill -0 "${pid}" 2>/dev/null && alive=$((alive + 1)) || true
      done <"${OUT_DIR}/pids.txt"
    fi
    [[ "${alive}" -eq 0 ]] && break
  fi
  sleep 1
done

got=0
for name in "${NAMES[@]}"; do
  if [[ -f "${name}.xstorelog" && -s "${name}.xstorelog" ]]; then
    mv -f "${name}.xstorelog" "${OUT_DIR}/"
    got=$((got + 1))
  else
    echo "warning: missing/empty ${name}.xstorelog (see ${OUT_DIR}/client_${name}.log)" >&2
    [[ -f "${name}.xstorelog" ]] && mv -f "${name}.xstorelog" "${OUT_DIR}/" || true
  fi
done
echo "found ${got}/${NCLIENTS} non-empty xstorelog files"

if [[ -f "${OUT_DIR}/pids.txt" ]]; then
  while read -r pid; do kill "${pid}" 2>/dev/null || true; done <"${OUT_DIR}/pids.txt"
  sleep 1
  while read -r pid; do kill -9 "${pid}" 2>/dev/null || true; done <"${OUT_DIR}/pids.txt"
fi

sleep 2
echo "done. logs: ${OUT_DIR}"
