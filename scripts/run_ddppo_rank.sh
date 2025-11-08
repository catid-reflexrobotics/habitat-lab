#!/usr/bin/env bash
#
# Multi-node DD-PPO launcher. Configure host-specific defaults below.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_NAME="rearrange/rl_skill.yaml"
NUM_ENVS=8
MASTER_PORT=23456
MASTER_HOST="ripper.lan"
NUM_NODES=2
DDPPO_ENV_FILE="${REPO_ROOT}/scripts/.ddppo_env"

if [[ -f "${DDPPO_ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${DDPPO_ENV_FILE}"
fi

MASTER_HOST="${DDPPO_MASTER_ADDR:-${MASTER_HOST}}"
MASTER_PORT="${DDPPO_MASTER_PORT:-${MASTER_PORT}}"
NUM_NODES="${DDPPO_NUM_NODES:-${NUM_NODES}}"

# hostname-specific settings
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
if [[ -n "${DDPPO_NODE_RANK:-}" ]]; then
  NODE_RANK="${DDPPO_NODE_RANK}"
  if [[ -n "${DDPPO_CUDA_DEVICES:-}" ]]; then
    CUDA_VISIBLE_DEVICES="${DDPPO_CUDA_DEVICES}"
  fi
else
  case "${HOSTNAME}" in
    ripper.lan)
      NODE_RANK=0
      CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
      ;;
    ripper2.lan)
      NODE_RANK=1
      CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
      ;;
    *)
      echo "Unknown host ${HOSTNAME}. Provide DDPPO_NODE_RANK (see scripts/setup_headless_server.sh)." >&2
      exit 1
      ;;
  esac
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/setup_headless_env.sh"
export CUDA_VISIBLE_DEVICES

IFS=',' read -r -a GPU_IDS <<< "${CUDA_VISIBLE_DEVICES}"
NUM_GPUS="${#GPU_IDS[@]}"

cd "${REPO_ROOT}"

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
