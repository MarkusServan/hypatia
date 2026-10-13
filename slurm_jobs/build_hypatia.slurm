#!/bin/bash
#SBATCH --account=share-ie-idi
#SBATCH --job-name=build_hypatia
#SBATCH --time=0-01:00:00
#SBATCH --partition=CPUQ
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16        # build.sh runs ./waf -j$SLURM_CPUS_PER_TASK
#SBATCH --mem=32G                 # Asking for 32GB RAM
#SBATCH --output=output.txt       # Specifying 'stdout'
#SBATCH --error=output.err        # Specifying 'stderr'
#SBATCH --mail-user=markase@ntnu.no
#SBATCH --mail-type=ALL

# Submit from a directory directly under the repo root: sbatch build_hypatia.slurm
WORKDIR=${SLURM_SUBMIT_DIR}
cd ${WORKDIR} || exit 1
echo "Running from this directory: $SLURM_SUBMIT_DIR"
echo "Name of job: $SLURM_JOB_NAME"
echo "ID of job: $SLURM_JOB_ID"
echo "The job was run on these nodes: $SLURM_JOB_NODELIST"

module purge

HYPATIA_DIR=$(realpath "${WORKDIR}/..")
IMAGE=${HYPATIA_DIR}/image/hypatia.sif

if [ ! -f "${IMAGE}" ]; then
  echo "Container image not found: ${IMAGE}"
  exit 1
fi
if [ ! -f "${HYPATIA_DIR}/hypatia_build.sh" ]; then
  echo "hypatia_build.sh not found in ${HYPATIA_DIR}"
  exit 1
fi

# Build ns3-sat-sim inside the container (all dependencies live in hypatia.sif)
apptainer exec --bind "${HYPATIA_DIR}" --pwd "${HYPATIA_DIR}" "${IMAGE}" \
  bash -c "git submodule update --init --recursive && bash hypatia_build.sh" || exit 1

echo "Hypatia build finished."
