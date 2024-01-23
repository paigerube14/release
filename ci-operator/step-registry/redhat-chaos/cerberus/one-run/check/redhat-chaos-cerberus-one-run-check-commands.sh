#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

return_status=$(cat "$ARTIFACT_DIR/cerberus.out"  | grep -c "1")

if [ $return_status -eq 0 ]; then
    exit 0
else
    exit 1
fi