#!/usr/bin/env bash

# This script runs the Flask application locally for testing.
# It runs the source code directly using Python, without Docker. 

set -euo pipefail

export DDB_TABLE="${DDB_TABLE:-guestbook-entries-demo}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export NODE_NAME="${NODE_NAME:-local-test}"

cd "$(dirname "$0")/.."
python3 app.py
