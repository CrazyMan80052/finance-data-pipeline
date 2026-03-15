#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:?PROJECT_ROOT must be set}"
BUILD_DIR="${BUILD_DIR:?BUILD_DIR must be set}"
LAMBDA_DIR="${PROJECT_ROOT}/lambda"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

python3 -m pip install \
  --requirement "${LAMBDA_DIR}/requirements.txt" \
  --target "${BUILD_DIR}"

cp "${LAMBDA_DIR}/transform.py" "${BUILD_DIR}/transform.py"

find "${BUILD_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "${BUILD_DIR}" -type f -name '*.pyc' -delete
