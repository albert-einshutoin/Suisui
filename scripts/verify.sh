#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"

mkdir -p "$BUILD_DIR"

CORE_SOURCES=()
while IFS= read -r source_file; do
  CORE_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/SoloPMCore" -name '*.swift' -print | sort)

APP_SOURCES=()
while IFS= read -r source_file; do
  APP_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/SoloPMApp" -name '*.swift' -print | sort)

swiftc \
  -emit-module \
  -emit-module-path "$BUILD_DIR/SoloPMCore.swiftmodule" \
  -emit-library \
  -enable-testing \
  -module-name SoloPMCore \
  "${CORE_SOURCES[@]}" \
  -lsqlite3 \
  -o "$BUILD_DIR/libSoloPMCore.dylib"

swiftc \
  -parse-as-library \
  -typecheck \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSoloPMCore \
  "${APP_SOURCES[@]}"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSoloPMCore \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR" \
  "${APP_SOURCES[@]}" \
  -o "$BUILD_DIR/SoloPMApp"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSoloPMCore \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR" \
  "$ROOT_DIR/Tests/Manual/SoloPMCoreManualTests.swift" \
  -o "$BUILD_DIR/SoloPMCoreManualTests"

"$BUILD_DIR/SoloPMCoreManualTests"
