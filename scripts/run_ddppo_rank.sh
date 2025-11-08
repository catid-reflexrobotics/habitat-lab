#!/usr/bin/env bash
#
# Multi-node DD-PPO launcher. Configure host-specific defaults below.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_NAME="rearrange/rl_skill.yaml"
NUM_ENVS=8
MASTER_PORT=23456
MASTER_HOST="ripper"
NUM_NODES=2
DDPPO_ENV_FILE="${REPO_ROOT}/scripts/.ddppo_env"

# shellcheck source=scripts/ddppo_common.sh
source "${REPO_ROOT}/scripts/ddppo_common.sh"

if [[ -f "${DDPPO_ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${DDPPO_ENV_FILE}"
fi

MASTER_HOST="${DDPPO_MASTER_ADDR:-${MASTER_HOST}}"
MASTER_PORT="${DDPPO_MASTER_PORT:-${MASTER_PORT}}"
NUM_NODES="${DDPPO_NUM_NODES:-${NUM_NODES}}"

# hostname-specific settings (ripper, ripper2)
HOST_FQDN="$(hostname -f 2>/dev/null || hostname)"
HOST_SHORT="$(hostname 2>/dev/null || echo "${HOST_FQDN}")"
HOST_DEFAULT_NODE_RANK=""
HOST_DEFAULT_GPUS=""

normalize_host() {
  local host="$1"
  printf '%s' "${host,,}"
}

declare -a HOST_LOOKUPS=()
HOST_LOOKUPS+=("$(normalize_host "${HOST_FQDN}")")
if [[ "${HOST_SHORT}" != "${HOST_FQDN}" ]]; then
  HOST_LOOKUPS+=("$(normalize_host "${HOST_SHORT}")")
fi

for host in "${HOST_LOOKUPS[@]}"; do
  case "${host}" in
    ripper|ripper.lan|ripper.local)
      HOST_DEFAULT_NODE_RANK=0
      HOST_DEFAULT_GPUS="0,1,2,3"
      break
      ;;
    ripper2|ripper2.lan|ripper2.local)
      HOST_DEFAULT_NODE_RANK=1
      HOST_DEFAULT_GPUS="0,1,2,3"
      break
      ;;
  esac
done

NODE_RANK="${DDPPO_NODE_RANK:-}"
if [[ -z "${NODE_RANK}" && -n "${HOST_DEFAULT_NODE_RANK}" ]]; then
  NODE_RANK="${HOST_DEFAULT_NODE_RANK}"
fi
if [[ -z "${NODE_RANK}" ]]; then
  echo "Unable to determine NODE_RANK for host ${HOST_FQDN}. Set DDPPO_NODE_RANK or run scripts/setup_headless_server.sh." >&2
  exit 1
fi

if [[ -n "${DDPPO_CUDA_DEVICES:-}" ]]; then
  CUDA_VISIBLE_DEVICES="${DDPPO_CUDA_DEVICES}"
elif [[ -z "${CUDA_VISIBLE_DEVICES:-}" && -n "${HOST_DEFAULT_GPUS}" ]]; then
  CUDA_VISIBLE_DEVICES="${HOST_DEFAULT_GPUS}"
fi

if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
  echo "CUDA_VISIBLE_DEVICES is not set. Export it or set DDPPO_CUDA_DEVICES." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/setup_headless_env.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/ddppo_env_utils.sh"
export CUDA_VISIBLE_DEVICES

ensure_rearrange_assets
ensure_rearrange_dataset

echo "[ddppo] Host=${HOST_FQDN} Rank=${NODE_RANK} GPUs=${CUDA_VISIBLE_DEVICES} Master=${MASTER_HOST}:${MASTER_PORT} Nodes=${NUM_NODES}"

IFS=',' read -r -a GPU_IDS <<< "${CUDA_VISIBLE_DEVICES}"
NUM_GPUS="${#GPU_IDS[@]}"

cd "${REPO_ROOT}"

# Keep Habitat's distributed rendezvous helpers (which read MAIN_{ADDR,PORT})
# in sync with torchrun's arguments so every rank connects to the same store.
export MAIN_ADDR="${MASTER_HOST}"
export MAIN_PORT="${MASTER_PORT}"

torchrun \
  --nnodes="${NUM_NODES}" \
  --node_rank="${NODE_RANK}" \
  --nproc_per_node="${NUM_GPUS}" \
  --master_addr="${MASTER_HOST}" \
  --master_port="${MASTER_PORT}" \
  habitat-baselines/habitat_baselines/run.py \
  --config-name="${CONFIG_NAME}" \
  habitat_baselines.num_environments="${NUM_ENVS}" \
  habitat_baselines.rl.ddppo.distrib_backend=gloo \
  habitat_baselines.tensorboard_dir="data/ddppo_logs" \
  habitat_baselines.checkpoint_folder="data/ddppo_ckpts"
