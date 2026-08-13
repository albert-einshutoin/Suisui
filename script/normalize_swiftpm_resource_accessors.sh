#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <swiftpm-build-directory>" >&2
  exit 2
fi

BUILD_DIRECTORY="${1%/}"
if [[ ! -d "$BUILD_DIRECTORY" || -L "$BUILD_DIRECTORY" ]]; then
  echo "BLOCKER: SwiftPM build directory is unavailable" >&2
  exit 1
fi

TARGET_BUNDLE_PAIRS=(
  "Suisui:Suisui_Suisui.bundle"
  "SuisuiCore:Suisui_SuisuiCore.bundle"
  "SwiftTerm:SwiftTerm_SwiftTerm.bundle"
)

count_fixed_lines() {
  local needle="$1"
  local file="$2"
  /usr/bin/grep -F -c "$needle" "$file" 2>/dev/null || true
}

for pair in "${TARGET_BUNDLE_PAIRS[@]}"; do
  target_name="${pair%%:*}"
  bundle_name="${pair#*:}"
  accessor="$BUILD_DIRECTORY/$target_name.build/DerivedSources/resource_bundle_accessor.swift"
  if [[ ! -f "$accessor" || -L "$accessor" ]]; then
    echo "BLOCKER: generated resource accessor is unavailable for $target_name" >&2
    exit 1
  fi

  original_main="let mainPath = Bundle.main.bundleURL.appendingPathComponent(\"$bundle_name\").path"
  portable_main="let mainPath = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(\"$bundle_name\").path"
  original_main_count="$(count_fixed_lines "$original_main" "$accessor")"
  portable_main_count="$(count_fixed_lines "$portable_main" "$accessor")"
  portable_build_count="$(count_fixed_lines "let buildPath = mainPath" "$accessor")"
  original_build_count="$(
    BUNDLE_NAME="$bundle_name" /usr/bin/perl -ne '
      BEGIN { $bundle = quotemeta($ENV{"BUNDLE_NAME"}); $count = 0 }
      $count += 1 if /^\s*let buildPath = "[^"\n]*\/$bundle"\s*$/;
      END { print $count }
    ' "$accessor"
  )"

  if [[ "$original_main_count" == "0" && "$portable_main_count" == "1" &&
        "$original_build_count" == "0" && "$portable_build_count" == "1" ]]; then
    continue
  fi
  if [[ "$original_main_count" != "1" || "$portable_main_count" != "0" ||
        "$original_build_count" != "1" || "$portable_build_count" != "0" ]]; then
    echo "BLOCKER: generated resource accessor template is unsupported for $target_name" >&2
    exit 1
  fi

  ORIGINAL_MAIN="$original_main" PORTABLE_MAIN="$portable_main" BUNDLE_NAME="$bundle_name" \
    /usr/bin/perl -0pi -e '
      my $original_main = quotemeta($ENV{"ORIGINAL_MAIN"});
      my $portable_main = $ENV{"PORTABLE_MAIN"};
      my $bundle = quotemeta($ENV{"BUNDLE_NAME"});
      my $main_replacements = s/$original_main/$portable_main/g;
      my $build_replacements = s{^([ \t]*)let buildPath = "[^"\n]*/$bundle"[ \t]*$}{${1}let buildPath = mainPath}gm;
      die "unexpected generated resource accessor replacement count\n"
        unless $main_replacements == 1 && $build_replacements == 1;
    ' "$accessor"

  if [[ "$(count_fixed_lines "$portable_main" "$accessor")" != "1" ||
        "$(count_fixed_lines "let buildPath = mainPath" "$accessor")" != "1" ]]; then
    echo "BLOCKER: generated resource accessor normalization failed for $target_name" >&2
    exit 1
  fi
done

printf 'OK: normalized native SwiftPM resource accessors for app-bundle portability\n'
