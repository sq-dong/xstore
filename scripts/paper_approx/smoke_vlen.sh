#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/dongshuqi/xstore
OUT=/home/dongshuqi/xstore/scripts/paper_approx/out/vlen_smoke.log
pkill -9 -f '[.]/ycsb_server' 2>/dev/null || true
sleep 2
cd "${ROOT}"
export MKL_THREADING_LAYER=SEQUENTIAL
export LD_LIBRARY_PATH="${ROOT}/deps/boost/lib:${ROOT}/deps/mkl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./ycsb_server --port=8888 --threads=8 --alloc_mem_m=7000 --use_nic_idx=0 \
  --len=16 --nkeys=1000000 --nmodels=1000 --ncheck_model=0 --vlen=true \
  --load_from_file=false --server_life_s=300 \
  >"${OUT}" 2>&1 &
SPID=$!
echo "started=${SPID}"
for i in $(seq 1 120); do
  if grep -q 'index related work done!' "${OUT}" 2>/dev/null; then
    echo "READY iter=${i}"
    exit 0
  fi
  if ! kill -0 "${SPID}" 2>/dev/null; then
    echo "DIED early"
    sed 's/\x1b\[[0-9;]*m//g' "${OUT}" | tail -40
    exit 1
  fi
  sleep 2
done
echo TIMEOUT
sed 's/\x1b\[[0-9;]*m//g' "${OUT}" | tail -40
exit 1
