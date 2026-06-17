#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"

mkdir -p "$BUILD_DIR"

CORE_SOURCES=(
  "$ROOT_DIR/Sources/SoloPMCore/App/AppSettings.swift"
  "$ROOT_DIR/Sources/SoloPMCore/App/MenuBarSummary.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Permissions/PermissionManager.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Shortcuts/ShortcutRegistration.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Security/SecretStore.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Security/KeychainSecretStore.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Audit/AuditLogger.swift"
  "$ROOT_DIR/Sources/SoloPMCore/Database/SQLiteDatabaseClient.swift"
)

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
  "$ROOT_DIR/Sources/SoloPMApp/SoloPMApp.swift"

swiftc \
  -parse-as-library \
  -I "$BUILD_DIR" \
  -L "$BUILD_DIR" \
  -lSoloPMCore \
  -Xlinker -rpath \
  -Xlinker "$BUILD_DIR" \
  "$ROOT_DIR/Sources/SoloPMApp/SoloPMApp.swift" \
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
