#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/porch-cell2jack-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc "$project_root/ios/Cell2JackPOC/Cell2JackVersionResult.swift" \
    "$project_root/ios/Cell2JackDriverTests/VersionParserTests.swift" -o "$test_directory/parser-tests"
"$test_directory/parser-tests"
xcrun clang++ -std=c++17 "$project_root/ios/Cell2JackDriverTests/ProtocolTests.cpp" -o "$test_directory/protocol-tests"
"$test_directory/protocol-tests"
