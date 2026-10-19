#!/usr/bin/env bash
set -euo pipefail
device_id="$1"
output="$2"
shift 2
scene_check="default"
if [[ " $* " == *" --preview-dynamic "* ]]; then scene_check="dynamic"; fi
# Interpreting the Swift checker costs seconds per screenshot; compile it once.
checker="ios/build/check-preview"
if [[ ! -x "$checker" || ios/scripts/check-preview.swift -nt "$checker" ]]; then
  mkdir -p ios/build
  swiftc -O ios/scripts/check-preview.swift -o "$checker.$$"
  mv "$checker.$$" "$checker"
fi
check_preview() {
  if [[ "$scene_check" == "dynamic" ]]; then
    "$checker" "$output" --dynamic
  else
    "$checker" "$output"
  fi
}
# Poll every 2 s for about 10 s per launch instead of sleeping 10 s. Keep the
# screenshot only when two polls in a row pass, so a mid-launch frame is not kept.
for attempt in {1..18}; do
  xcrun simctl launch --terminate-running-process "$device_id" com.ethanteng.helloporch "$@"
  passes=0
  for poll in {1..5}; do
    sleep 2
    xcrun simctl io "$device_id" screenshot "$output"
    if check_preview; then
      passes=$((passes + 1))
      if [[ "$passes" == 2 ]]; then
        echo "Porch is visible: $output"
        exit 0
      fi
    else
      passes=0
    fi
  done
done
echo 'The simulator never displayed Porch; screenshot verification failed.' >&2
exit 1
