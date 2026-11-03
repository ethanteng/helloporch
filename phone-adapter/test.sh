#!/bin/sh
# Host tests for the phone adapter's parser, keys and session. No hardware needed.
# Pass raw Cell2Jack captures to also print what the adapter would type for them.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src="$here/firmware/porch_phone_adapter"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
${CC:-cc} -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$src" \
  "$here/tests/adapter_tests.c" "$src/cell2jack_parser.c" "$src/cell2jack_session.c" "$src/porch_keys.c" \
  -o "$out/adapter_tests"
"$out/adapter_tests" "$@"
