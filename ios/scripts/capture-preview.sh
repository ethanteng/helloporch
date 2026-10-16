#!/usr/bin/env bash
set -euo pipefail
device_id="$1"
output="$2"
shift 2
scene_check="default"
if [[ " $* " == *" --preview-dynamic "* ]]; then scene_check="dynamic"; fi
check_preview() {
  if [[ "$scene_check" == "dynamic" ]]; then
    swift ios/scripts/check-preview.swift "$output" --dynamic
  else
    swift ios/scripts/check-preview.swift "$output"
  fi
}
for attempt in {1..18}; do
  xcrun simctl launch --terminate-running-process "$device_id" com.ethanteng.helloporch "$@"
  sleep 10
  xcrun simctl io "$device_id" screenshot "$output"
  if check_preview; then
    echo "Porch is visible: $output"
    exit 0
  fi
done
echo 'The simulator never displayed Porch; screenshot verification failed.' >&2
exit 1
