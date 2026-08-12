#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <native-swiftpm-build-plan> <standalone-build-plan>" >&2
  exit 2
fi

SOURCE_PLAN="$1"
DESTINATION_PLAN="$2"

if [[ ! -f "$SOURCE_PLAN" || -L "$SOURCE_PLAN" ]]; then
  echo "BLOCKER: native SwiftPM build plan is unavailable" >&2
  exit 1
fi
if [[ -L "$DESTINATION_PLAN" ]]; then
  echo "BLOCKER: standalone SwiftPM build plan destination must not be a symlink" >&2
  exit 1
fi

client_count="$(/usr/bin/grep -c '^  name: basic$' "$SOURCE_PLAN" 2>/dev/null || true)"
if [[ "$client_count" != "1" ]]; then
  echo "BLOCKER: native SwiftPM build plan client is unsupported" >&2
  exit 1
fi

while IFS= read -r tool_name; do
  case "$tool_name" in
    shell|phony|write-auxiliary-file|copy-tool|package-structure-tool|test-discovery-tool|test-entry-point-tool)
      ;;
    *)
      echo "BLOCKER: native SwiftPM build plan contains unsupported tool: $tool_name" >&2
      exit 1
      ;;
  esac
done < <(/usr/bin/awk '/^    tool: / { print $2 }' "$SOURCE_PLAN" | LC_ALL=C /usr/bin/sort -u)

/bin/cp "$SOURCE_PLAN" "$DESTINATION_PLAN"

# The standalone llbuild client cannot instantiate SwiftPM's planning-only
# tools. The first native build has already materialized those outputs, so the
# relink graph deliberately treats them as immutable prerequisites and runs
# only the compiler/linker shell commands against the normalized accessors.
/usr/bin/perl -0pi -e '
  my $client_replacements = s/^  name: basic$/  name: swift-build/mg;
  my $tool_replacements = s/^    tool: (?:write-auxiliary-file|copy-tool|package-structure-tool|test-discovery-tool|test-entry-point-tool)$/    tool: phony/mg;
  die "unexpected SwiftPM build-plan client replacement count\n"
    unless $client_replacements == 1;
' "$DESTINATION_PLAN"

if [[ "$(/usr/bin/grep -c '^  name: swift-build$' "$DESTINATION_PLAN" 2>/dev/null || true)" != "1" ]]; then
  echo "BLOCKER: standalone SwiftPM build plan client normalization failed" >&2
  exit 1
fi
if /usr/bin/grep -Eq '^    tool: (write-auxiliary-file|copy-tool|package-structure-tool|test-discovery-tool|test-entry-point-tool)$' "$DESTINATION_PLAN"; then
  echo "BLOCKER: standalone SwiftPM build plan still contains planning-only tools" >&2
  exit 1
fi

printf 'OK: prepared standalone native SwiftPM relink manifest\n'
