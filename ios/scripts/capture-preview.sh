#!/usr/bin/env bash
set -euo pipefail
device_id="$1"
output="$2"
shift 2
for attempt in {1..18}; do
  xcrun simctl launch --terminate-running-process "$device_id" com.ethanteng.helloporch "$@"
  sleep 10
  xcrun simctl io "$device_id" screenshot "$output"
  if swift ios/scripts/check-preview.swift "$output"; then
    echo "Porch is visible: $output"
    exit 0
  fi
done
echo 'The simulator never displayed Porch; screenshot verification failed.' >&2
exit 1
