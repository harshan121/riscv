#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$root"
comparator_benchmark/signed_le_experiment/scripts/run_verification.sh
comparator_benchmark/signed_le_experiment/scripts/run_formal.sh
comparator_benchmark/signed_le_experiment/scripts/run_synthesis.sh
