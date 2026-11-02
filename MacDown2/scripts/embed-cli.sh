#!/bin/bash
set -euo pipefail

source_executable="${SCRIPT_INPUT_FILE_0}"
destination_executable="${SCRIPT_OUTPUT_FILE_0}"
test -f "$source_executable"
test -x "$source_executable"
/usr/bin/install -m 755 "$source_executable" "$destination_executable"
/usr/bin/cmp "$source_executable" "$destination_executable"

source_resources="${SCRIPT_INPUT_FILE_1}"
destination_resources="${SCRIPT_OUTPUT_FILE_1}"
test -d "$source_resources"
/usr/bin/ditto "$source_resources" "$destination_resources"
/usr/bin/diff -rq "$source_resources" "$destination_resources"
