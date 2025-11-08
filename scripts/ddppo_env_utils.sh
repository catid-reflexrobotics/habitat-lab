#!/usr/bin/env bash
#
# Common helpers shared by DD-PPO launcher scripts.

if [[ -n "${__HABLAB_DDPPO_ENV_UTILS_SOURCED:-}" ]]; then
  return
fi
__HABLAB_DDPPO_ENV_UTILS_SOURCED=1

ensure_rearrange_assets() {
  if [[ -z "${REPO_ROOT:-}" ]]; then
    echo "[ddppo] REPO_ROOT is not set; cannot locate the data directory." >&2
    return 1
  fi

  local data_root="${REPO_ROOT}/data"
  local dataset_file="${data_root}/datasets/replica_cad/rearrange/v2/train/rearrange_easy.json.gz"

  if [[ -f "${dataset_file}" ]]; then
    return 0
  fi

  echo "[ddppo] Missing ReplicaCAD rearrange dataset at ${dataset_file}"
  echo "[ddppo] Downloading required assets via habitat_sim.utils.datasets_download (this may take a while)..."

  mkdir -p "${data_root}"
  python -m habitat_sim.utils.datasets_download \
    --uids rearrange_task_assets \
    --data-path "${data_root}" \
    --no-replace
}
