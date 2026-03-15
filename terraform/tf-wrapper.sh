#!/usr/bin/env bash
# tf-wrapper.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: .env file not found at ${ENV_FILE}"
  exit 1
fi

# Load .env, ignoring comments and empty lines
set -a
source <(grep -v '^#' "${ENV_FILE}" | grep -v '^$')
set +a

# Validate required variables
REQUIRED_VARS=("TF_VAR_aws_region" "TF_VAR_alpha_vantage_api_key")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Required variable $var not set in .env"
    exit 1
  fi
done

terraform -chdir="${SCRIPT_DIR}" "$@"