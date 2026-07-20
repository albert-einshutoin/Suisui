#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"

mkdir -p "$BUILD_DIR"

CORE_SOURCES=()
while IFS= read -r source_file; do
  CORE_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/SuisuiCore" -name '*.swift' -print | sort)

APP_SOURCES=()
while IFS= read -r source_file; do
  APP_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/SuisuiApp" -name '*.swift' -print | sort)

swiftc \
  -emit-module \
  -emit-module-path "$BUILD_DIR/SuisuiCore.swiftmodule" \
  -emit-library \
  -enable-testing \
  -module-name SuisuiCore \
  "${CORE_SOURCES[@]}" \
  -lsqlite3 \
  -o "$BUILD_DIR/libSuisuiCore.dylib"

swiftc \
  -parse-as-library \
  -typecheck \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSuisuiCore \
  "${APP_SOURCES[@]}"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSuisuiCore \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR" \
  "${APP_SOURCES[@]}" \
  -o "$BUILD_DIR/SuisuiApp"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSuisuiCore \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR" \
  "$ROOT_DIR/Tests/Manual/SuisuiCoreManualTests.swift" \
  -o "$BUILD_DIR/SuisuiCoreManualTests"

"$BUILD_DIR/SuisuiCoreManualTests"
