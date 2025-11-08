#!/usr/bin/env bash
#
# Single-node DD-PPO launcher (kept for backwards compatibility).
#
# For multi-node runs see run_ddppo_rank.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_NAME="rearrange/rl_skill.yaml"
NUM_ENVS=8
MASTER_PORT=23456

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/setup_headless_env.sh"

if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
  export CUDA_VISIBLE_DEVICES="0,1,2,3"
fi

IFS=',' read -r -a GPU_IDS <<< "${CUDA_VISIBLE_DEVICES}"
NUM_GPUS="${#GPU_IDS[@]}"

cd "${REPO_ROOT}"

torchrun --nproc_per_node="${NUM_GPUS}" --master_port="${MASTER_PORT}" \
  habitat-baselines/habitat_baselines/run.py \
  --config-name="${CONFIG_NAME}" \
  habitat_baselines.num_environments="${NUM_ENVS}" \
  habitat_baselines.rl.ddppo.distrib_backend=gloo \
  habitat_baselines.tensorboard_dir="data/ddppo_logs" \
  habitat_baselines.checkpoint_folder="data/ddppo_ckpts"
