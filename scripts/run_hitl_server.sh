#!/usr/bin/env bash
#
# Launch the headless HITL server (pick_throw_vr example) with sane defaults.
# Usage:
#   scripts/run_hitl_server.sh [--port 18000] [--data-path /path/to/data] [extra hydra args...]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PORT=18000
DATA_PATH="${REPO_ROOT}/data"
PORT="${DEFAULT_PORT}"
GPU_LIST="${DEFAULT_GPU_LIST:-0}"

usage() {
  grep '^#' "$0" | cut -c3-
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --gpus)
      GPU_LIST="$2"
      shift 2
      ;;
    --data-path)
      DATA_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ ! -d "${DATA_PATH}" ]]; then
  echo "Data path '${DATA_PATH}' not found. Download datasets first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/setup_headless_env.sh"

cd "${REPO_ROOT}"

IFS=',' read -r -a GPU_IDS <<< "${GPU_LIST}"
if [[ "${#GPU_IDS[@]}" -eq 0 ]]; then
  echo "No GPUs specified via --gpus" >&2
  exit 1
fi

pids=()
cleanup() {
  if [[ "${#pids[@]}" -gt 0 ]]; then
    echo "Stopping ${#pids[@]} HITL server(s)..."
    kill "${pids[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for idx in "${!GPU_IDS[@]}"; do
  GPU="${GPU_IDS[$idx]}"
  PORT_OFFSET=$((PORT + idx))
  LOG_PREFIX="[gpu${GPU}:port${PORT_OFFSET}]"
  (
    export MAGNUM_DEVICE="${GPU}"
    export MAGNUM_CUDA_DEVICE="${GPU}"
    python examples/hitl/pick_throw_vr/pick_throw_vr.py \
      +experiment=headless_server \
      habitat_hitl.networking.enable=True \
      habitat_hitl.networking.port="${PORT_OFFSET}" \
      habitat.simulator.habitat_sim_v0.gpu_device_id="${GPU}" \
      +data.dir="${DATA_PATH}" \
      "$@"
  ) 2>&1 | sed -u "s/^/${LOG_PREFIX} /" &
  pids+=($!)
  echo "${LOG_PREFIX} launched."
done

wait "${pids[@]}"
