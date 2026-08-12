#!/usr/bin/env bash

# Shared public-artifact redaction contract. Keep every CI stream that may be
# uploaded on this single allowlist so new diagnostics cannot silently expose a
# provider credential or a machine-local path.
ci_redact_stream() {
  sed -E \
    -e 's#/(Users|Volumes)/[^[:space:]]+#<path>#g' \
    -e 's#/private/var/folders/[^[:space:]]+#<temp-path>#g' \
    -e 's#(/var)?/tmp/[^[:space:]]+#<temp-path>#g' \
    -e 's#(Authorization[[:space:]]*:[[:space:]]*Bearer)[[:space:]]+[^[:space:]]+#\1 <redacted>#Ig' \
    -e 's#(^|[^[:alnum:]_])sk-[A-Za-z0-9_-]{8,}#\1<redacted>#g' \
    -e 's#github_pat_[A-Za-z0-9_]{8,}#<redacted>#g' \
    -e 's#gh[pousr]_[A-Za-z0-9_]{8,}#<redacted>#g' \
    -e 's#xox[baprs]-[A-Za-z0-9-]{8,}#<redacted>#g' \
    -e 's#AKIA[0-9A-Z]{16}#<redacted>#g' \
    -e 's#("[[:alnum:]_.-]*(token|secret|password|api[_-]?key)"[[:space:]]*:[[:space:]]*)"[^"]*"#\1"<redacted>"#Ig' \
    -e "s#('[[:alnum:]_.-]*(token|secret|password|api[_-]?key)'[[:space:]]*:[[:space:]]*)'[^']*'#\\1'<redacted>'#Ig" \
    -e 's#([[:alnum:]_.-]*(token|secret|password|api[_-]?key))[[:space:]]*[=:][[:space:]]*[^[:space:]]+#\1=<redacted>#Ig' \
    -e 's#[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}#<redacted-email>#g' \
    -e 's#[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}#<redacted-uuid>#g'
}
