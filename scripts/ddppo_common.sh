#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for DD-PPO launcher scripts.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "scripts/ddppo_common.sh must be sourced, not executed directly." >&2
  exit 1
fi

ensure_rearrange_dataset() {
  local dataset_root="${REPO_ROOT}/data/datasets/replica_cad/rearrange/v2"
  local train_glob="${dataset_root}/train/*.json.gz"

  if compgen -G "${train_glob}" > /dev/null 2>&1; then
    return
  fi

  echo "[ddppo] ReplicaCAD rearrange dataset not found under ${dataset_root}"
  echo "[ddppo] Downloading dataset via habitat_sim.utils.datasets_download (this may take a while)."

  if ! command -v python >/dev/null 2>&1; then
    echo "[ddppo] Python interpreter not found. Activate your Habitat environment before running the DD-PPO launcher." >&2
    return 1
  fi

  python -m habitat_sim.utils.datasets_download \
    --no-replace \
    --data-path "${REPO_ROOT}/data" \
    --uids rearrange_task_assets
}
