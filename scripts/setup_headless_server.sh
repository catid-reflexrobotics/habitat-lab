#!/usr/bin/env bash
#
# Configure a headless Ubuntu server so Habitat-Lab's DD-PPO runners
# can be launched remotely (scripts/run_ddppo_rank.sh).
#
# Usage:
#   bash scripts/setup_headless_server.sh [options]
#
# Run with --help to see optional arguments. The script is idempotent and can
# be re-run whenever the environment needs to be updated.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONDA_PREFIX="${HOME}/miniconda3"
CONDA_PREFIX="${DEFAULT_CONDA_PREFIX}"
CONDA_ENV_NAME="habitat"
PYTHON_VERSION="3.9"
CMAKE_VERSION="3.26.4"
TORCH_VERSION="2.2.2"
TORCHVISION_VERSION="0.17.2"
TORCHAUDIO_VERSION="2.2.2"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu121}"
APT_PACKAGES=(
  build-essential
  git
  curl
  wget
  ca-certificates
  pkg-config
  libjpeg-dev
  libpng-dev
  libegl1
  libegl1-mesa-dev
  libglfw3-dev
  libx11-dev
  libomp-dev
  libglm-dev
  libxi-dev
  unzip
  tmux
  screen
)
DOWNLOAD_UIDS=("rearrange_task_assets")
DDPPO_ENV_FILE="${REPO_ROOT}/scripts/.ddppo_env"
MASTER_ADDR_DEFAULT="$(hostname -f 2>/dev/null || hostname)"
DDPPO_MASTER_ADDR="${MASTER_ADDR_DEFAULT}"
DDPPO_MASTER_PORT="23456"
DDPPO_NUM_NODES="2"
DDPPO_NODE_RANK="${DDPPO_NODE_RANK:-0}"
DDPPO_CUDA_DEVICES="${CUDA_VISIBLE_DEVICES:-0,1,2,3}"
SKIP_APT=0
SKIP_CONDA_INSTALL=0
SKIP_DATASETS=0
SKIP_ENV_FILE=0

usage() {
  cat <<'USAGE'
Usage: scripts/setup_headless_server.sh [options]

Options:
  --conda-prefix PATH     Path where Miniconda will be installed (default: ~/miniconda3)
  --env-name NAME         Conda environment name to create/use (default: habitat)
  --python VERSION        Python version for the environment (default: 3.9)
  --cmake VERSION         CMake version for the environment (default: 3.26.4)
  --torch VERSION         PyTorch version to install (default: 2.2.2)
  --torchvision VERSION   Torchvision version (default: 0.17.2)
  --torchaudio VERSION    Torchaudio version (default: 2.2.2)
  --torch-index URL       Wheel index URL for PyTorch install (default: cu121 wheels)
  --master-addr HOST      Default master address used by run_ddppo_rank.sh
  --master-port PORT      Default master port (default: 23456)
  --num-nodes N           Total nodes participating in DD-PPO (default: 2)
  --node-rank R           Rank for this server (default: 0)
  --cuda-devices LIST     CUDA_VISIBLE_DEVICES string (default: 0,1,2,3 or env)
  --env-file PATH         Where to write the DD-PPO env file (default: scripts/.ddppo_env)
  --skip-apt              Skip apt-get install of system packages
  --skip-conda-install    Assume conda is already installed; skip installer
  --skip-datasets         Skip dataset/weights download steps
  --skip-env-file         Do not write the DD-PPO env helper file
  -h, --help              Show this message and exit
USAGE
}

log() {
  printf '[setup] %s\n' "$*"
}

require_arg() {
  if [[ -z "${2:-}" ]]; then
    printf 'error: %s requires a non-empty argument\n' "$1" >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --conda-prefix)
      shift
      require_arg "--conda-prefix" "${1:-}"
      CONDA_PREFIX="$1"
      ;;
    --env-name)
      shift
      require_arg "--env-name" "${1:-}"
      CONDA_ENV_NAME="$1"
      ;;
    --python)
      shift
      require_arg "--python" "${1:-}"
      PYTHON_VERSION="$1"
      ;;
    --cmake)
      shift
      require_arg "--cmake" "${1:-}"
      CMAKE_VERSION="$1"
      ;;
    --torch)
      shift
      require_arg "--torch" "${1:-}"
      TORCH_VERSION="$1"
      ;;
    --torchvision)
      shift
      require_arg "--torchvision" "${1:-}"
      TORCHVISION_VERSION="$1"
      ;;
    --torchaudio)
      shift
      require_arg "--torchaudio" "${1:-}"
      TORCHAUDIO_VERSION="$1"
      ;;
    --torch-index)
      shift
      require_arg "--torch-index" "${1:-}"
      TORCH_INDEX_URL="$1"
      ;;
    --master-addr)
      shift
      require_arg "--master-addr" "${1:-}"
      DDPPO_MASTER_ADDR="$1"
      ;;
    --master-port)
      shift
      require_arg "--master-port" "${1:-}"
      DDPPO_MASTER_PORT="$1"
      ;;
    --num-nodes)
      shift
      require_arg "--num-nodes" "${1:-}"
      DDPPO_NUM_NODES="$1"
      ;;
    --node-rank)
      shift
      require_arg "--node-rank" "${1:-}"
      DDPPO_NODE_RANK="$1"
      ;;
    --cuda-devices)
      shift
      require_arg "--cuda-devices" "${1:-}"
      DDPPO_CUDA_DEVICES="$1"
      ;;
    --env-file)
      shift
      require_arg "--env-file" "${1:-}"
      DDPPO_ENV_FILE="$1"
      ;;
    --skip-apt)
      SKIP_APT=1
      ;;
    --skip-conda-install)
      SKIP_CONDA_INSTALL=1
      ;;
    --skip-datasets)
      SKIP_DATASETS=1
      ;;
    --skip-env-file)
      SKIP_ENV_FILE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

run_apt_installs() {
  if [[ "${SKIP_APT}" -eq 1 ]]; then
    log "Skipping apt installs (--skip-apt)."
    return
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not found; skipping system package installation."
    return
  fi
  local sudo_cmd=""
  if command -v sudo >/dev/null 2>&1 && [[ "${EUID}" -ne 0 ]]; then
    sudo_cmd="sudo"
  elif [[ "${EUID}" -ne 0 ]]; then
    log "Not running as root and sudo unavailable; skipping system packages."
    return
  fi
  log "Installing system dependencies via apt-get."
  ${sudo_cmd} apt-get update
  ${sudo_cmd} apt-get install -y "${APT_PACKAGES[@]}"
}

install_miniconda() {
  if [[ -x "${CONDA_PREFIX}/bin/conda" ]]; then
    log "Conda already installed at ${CONDA_PREFIX}"
    return
  fi
  if [[ "${SKIP_CONDA_INSTALL}" -eq 1 ]]; then
    log "Conda not found at ${CONDA_PREFIX} and --skip-conda-install was provided."
    return 1
  fi
  log "Installing Miniconda into ${CONDA_PREFIX}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -fsSL -o "${tmp_dir}/miniconda.sh" \
    https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  bash "${tmp_dir}/miniconda.sh" -b -p "${CONDA_PREFIX}"
  rm -rf "${tmp_dir}"
}

ensure_conda_env() {
  # shellcheck disable=SC1091
  source "${CONDA_PREFIX}/etc/profile.d/conda.sh"
  if conda info --envs | awk '{print $1}' | grep -Fxq "${CONDA_ENV_NAME}"; then
    log "Updating existing conda env ${CONDA_ENV_NAME}"
    conda install -y -n "${CONDA_ENV_NAME}" "python=${PYTHON_VERSION}" "cmake=${CMAKE_VERSION}"
  else
    log "Creating conda env ${CONDA_ENV_NAME}"
    conda create -y -n "${CONDA_ENV_NAME}" "python=${PYTHON_VERSION}" "cmake=${CMAKE_VERSION}"
  fi
  conda activate "${CONDA_ENV_NAME}"
}

install_python_packages() {
  log "Installing PyTorch ${TORCH_VERSION} (index: ${TORCH_INDEX_URL})"
  python -m pip install --upgrade pip setuptools wheel
  python -m pip install \
    --index-url "${TORCH_INDEX_URL}" \
    "torch==${TORCH_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}"

  log "Installing habitat-sim (with bullet) from conda-forge/aihabitat"
  conda install -y -c conda-forge -c aihabitat habitat-sim withbullet

  log "Installing habitat-lab and habitat-baselines in editable mode"
  python -m pip install -e "${REPO_ROOT}/habitat-lab"
  python -m pip install -e "${REPO_ROOT}/habitat-baselines"
}

download_datasets() {
  if [[ "${SKIP_DATASETS}" -eq 1 ]]; then
    log "Skipping dataset download (--skip-datasets)."
    return
  fi
  log "Downloading ReplicaCAD rearrange assets (this can take a while)"
  python -m habitat_sim.utils.datasets_download \
    --no-replace \
    --data-path "${REPO_ROOT}/data" \
    --uids "${DOWNLOAD_UIDS[@]}"

  local models_dir="${REPO_ROOT}/data/ddppo-models"
  if [[ ! -d "${models_dir}" ]]; then
    log "Fetching DD-PPO pretrained weights"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "${tmp_dir}/ddppo-models.zip" \
      https://dl.fbaipublicfiles.com/habitat/data/baselines/v1/ddppo/ddppo-models.zip
    unzip -q "${tmp_dir}/ddppo-models.zip" -d "${tmp_dir}"
    mkdir -p "${REPO_ROOT}/data"
    mv "${tmp_dir}/ddppo-models" "${models_dir}"
    rm -rf "${tmp_dir}"
  else
    log "DD-PPO pretrained weights already exist at ${models_dir}"
  fi
}

write_ddppo_env_file() {
  if [[ "${SKIP_ENV_FILE}" -eq 1 ]]; then
    log "Skipping DD-PPO env file creation (--skip-env-file)."
    return
  fi
  mkdir -p "$(dirname "${DDPPO_ENV_FILE}")"
  cat > "${DDPPO_ENV_FILE}" <<EOF
# Auto-generated by setup_headless_server.sh on $(date)
export DDPPO_MASTER_ADDR="${DDPPO_MASTER_ADDR}"
export DDPPO_MASTER_PORT="${DDPPO_MASTER_PORT}"
export DDPPO_NUM_NODES="${DDPPO_NUM_NODES}"
export DDPPO_NODE_RANK="${DDPPO_NODE_RANK}"
export DDPPO_CUDA_DEVICES="${DDPPO_CUDA_DEVICES}"
EOF
  log "Wrote DD-PPO defaults to ${DDPPO_ENV_FILE}"
}

ensure_ubuntu() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log "Warning: expected Ubuntu but detected ${NAME:-unknown}. Continuing anyway."
    fi
  fi
}

main() {
  ensure_ubuntu
  run_apt_installs
  install_miniconda
  ensure_conda_env
  install_python_packages
  download_datasets
  write_ddppo_env_file

  local env_note="not written (--skip-env-file)."
  if [[ "${SKIP_ENV_FILE}" -eq 0 ]]; then
    env_note="${DDPPO_ENV_FILE}"
  fi

  cat <<SUMMARY

============================================================
Habitat-Lab headless setup complete.

- Conda prefix : ${CONDA_PREFIX}
- Environment  : ${CONDA_ENV_NAME}
- DD-PPO env   : ${env_note}

Next steps:
  1. SSH into each node, run this script (set --node-rank accordingly).
  2. On every session source scripts/setup_headless_env.sh
     (run_ddppo_rank.sh does this automatically).
  3. Launch training with scripts/run_ddppo_rank.sh.
============================================================
SUMMARY
}

main "$@"
