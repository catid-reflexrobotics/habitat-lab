#!/usr/bin/env bash
#
# Usage:
#   source scripts/setup_headless_env.sh
# The script activates the habitat conda environment (if not already active)
# and exports the environment variables that are needed so that Habitat-Sim
# can create an EGL context on this headless machine.

set -euo pipefail

if [[ "${CONDA_DEFAULT_ENV:-}" != "habitat" ]]; then
  if [[ ! -f "${HOME}/miniconda3/etc/profile.d/conda.sh" ]]; then
    echo "Cannot find miniconda at \$HOME/miniconda3. Please adjust the path in scripts/setup_headless_env.sh." >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "${HOME}/miniconda3/etc/profile.d/conda.sh"
  conda activate habitat
fi

# Force GLVND to load the NVIDIA vendor ICD so Windowless EGL can find a GPU.
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
# Prevent Magnum from trying to create an onscreen GLFW window.
export MAGNUM_DISABLE_GLFW_WINDOW=1
# Turn down Habitat-Sim logging noise for CLI demos.
export HABITAT_SIM_LOG=${HABITAT_SIM_LOG:-ERROR}
# Silence the legacy Gym deprecation warning to keep demo logs readable.
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore:::gym}"

echo "Habitat headless environment is ready (conda env: ${CONDA_DEFAULT_ENV})."
