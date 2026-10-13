#!/bin/bash
#SBATCH --account=markase
#SBATCH --job-name=generate_constellation
#SBATCH --time=0-04:00:00
#SBATCH --partition=CPUQ
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16        # Forwarding state is calculated with $SLURM_CPUS_PER_TASK processes
#SBATCH --mem=32G                 # Asking for 32GB RAM
#SBATCH --output=generate_constellation.txt   # Specifying 'stdout'
#SBATCH --error=generate_constellation.err    # Specifying 'stderr'
#SBATCH --mail-user=markase@ntnu.no
#SBATCH --mail-type=ALL

# Generates a constellation (static network description + forwarding state), extracts the
# path between two ground stations over time, and creates the satviz visualizations.
#
# Submit from a directory directly under the repo root: sbatch generate_constellation.slurm
# The settings below can be overridden, e.g.:
#   sbatch --export=ALL,SRC_GS=24,DST_GS=66 generate_constellation.slurm

MAIN=${MAIN:-main_starlink_550.py}                  # Generation script in constellations/
CONFIG=${CONFIG:-config_starlink_550_one_orbit.txt} # Config file in constellations/ (or an absolute path)
SRC_GS=${SRC_GS:-0}                                 # Ground station ids (first column of ground_stations.txt) Tokio
DST_GS=${DST_GS:-9}                                 #New York
GEN_TIME_MS=${GEN_TIME_MS:-0}                       # Time for which the path is visualized

WORKDIR=${SLURM_SUBMIT_DIR}
cd ${WORKDIR} || exit 1
echo "Running from this directory: $SLURM_SUBMIT_DIR"
echo "Name of job: $SLURM_JOB_NAME"
echo "ID of job: $SLURM_JOB_ID"
echo "The job was run on these nodes: $SLURM_JOB_NODELIST"

module purge

HYPATIA_DIR=$(realpath "${WORKDIR}/..")
IMAGE=${HYPATIA_DIR}/image/hypatia.sif
CONSTELLATIONS_DIR=${HYPATIA_DIR}/constellations

if [ ! -f "${IMAGE}" ]; then
  echo "Container image not found: ${IMAGE}"
  exit 1
fi
case "${CONFIG}" in
/*) ;;
*) CONFIG=${CONSTELLATIONS_DIR}/${CONFIG} ;;
esac
if [ ! -f "${CONSTELLATIONS_DIR}/${MAIN}" ] || [ ! -f "${CONFIG}" ]; then
  echo "Generation script or config not found: ${CONSTELLATIONS_DIR}/${MAIN}, ${CONFIG}"
  exit 1
fi

# Run a command inside the container (all dependencies live in hypatia.sif)
in_container() {
  local pwd_dir=$1
  shift
  apptainer exec --bind "${HYPATIA_DIR}" --pwd "${pwd_dir}" \
    --env "SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK}" "${IMAGE}" "$@"
}

config_value() {
  grep "^$1=" "${CONFIG}" | tail -n 1 | cut -d= -f2 | tr -d '[:space:]'
}

# 1. Static network description and forwarding state
in_container "${CONSTELLATIONS_DIR}" python "${MAIN}" --config "${CONFIG}" || exit 1

# The name of the generated constellation follows from the generation script and the config
BASE_NAME=$(grep '^BASE_NAME = ' "${CONSTELLATIONS_DIR}/${MAIN}" | cut -d'"' -f2)
NAME=${BASE_NAME}_$(config_value isl_selection)_$(config_value gs_selection)_$(config_value dynamic_state_algorithm)
NETWORK_DIR=${CONSTELLATIONS_DIR}/gen_data/${NAME}
DURATION_S=$(config_value duration_s)
TIME_STEP_MS=$(config_value time_step_ms)
if [ ! -f "${NETWORK_DIR}/tles.txt" ]; then
  echo "Generated constellation not found: ${NETWORK_DIR}"
  exit 1
fi
echo "Generated constellation: ${NETWORK_DIR}"

# 2. Path between the two ground stations over time
# Node ids of ground stations come after those of the satellites
read -r NUM_ORBS NUM_SATS_PER_ORB <"${NETWORK_DIR}/tles.txt"
SRC=$((NUM_ORBS * NUM_SATS_PER_ORB + SRC_GS))
DST=$((NUM_ORBS * NUM_SATS_PER_ORB + DST_GS))
ANALYSIS_DIR=${CONSTELLATIONS_DIR}/analysis_data
in_container "${HYPATIA_DIR}/satgenpy" python -m satgen.post_analysis.main_print_routes_and_rtt \
  "${ANALYSIS_DIR}" "${NETWORK_DIR}" "${TIME_STEP_MS}" "${DURATION_S}" "${SRC}" "${DST}" || exit 1
PATH_FILE=${ANALYSIS_DIR}/${NAME}/${TIME_STEP_MS}ms_for_${DURATION_S}s/manual/data/networkx_path_${SRC}_to_${DST}.txt
echo "Path file: ${PATH_FILE}"

# 3. Visualizations (need the Cesium access token)
if [ -z "${CESIUM_ACCESS_TOKEN}" ] && [ ! -f "${HYPATIA_DIR}/satviz/cesium_token.txt" ]; then
  echo "No Cesium access token (CESIUM_ACCESS_TOKEN or satviz/cesium_token.txt): skipping the visualizations."
  echo "Constellation generation finished."
  exit 0
fi
in_container "${HYPATIA_DIR}/satviz/scripts" python visualize_constellation.py "${NETWORK_DIR}" || exit 1
in_container "${HYPATIA_DIR}/satviz/scripts" python visualize_path.py "${NETWORK_DIR}" "${PATH_FILE}" "${GEN_TIME_MS}" || exit 1

echo "Constellation generation finished. Visualizations are in ${HYPATIA_DIR}/satviz/viz_output"
