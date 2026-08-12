#!/usr/bin/env bash

# Shared public-artifact redaction contract. Keep every CI stream that may be
# uploaded on this single allowlist so new diagnostics cannot silently expose a
# provider credential or a machine-local path.
ci_redact_stream() {
  LC_ALL=C /usr/bin/perl -ne '
    if ($inside_private_key) {
      $inside_private_key = 0 if /-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/;
      next;
    }
    if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/) {
      print "<redacted>\n";
      $inside_private_key = 1;
      next;
    }
    if (m{/(?:Users|Volumes)/}) {
      print "<path>\n";
      next;
    }
    if (m{/(?:private/)?var/folders/} || m{(?:^|[[:space:]"\x27])(?:/var)?/tmp/}) {
      print "<temp-path>\n";
      next;
    }
    if (
      /Authorization\s*:\s*(?:Bearer|Basic)\s+/i ||
      m{https?://[^/@\s:]+:[^/@\s]+@}i ||
      /(?:^|[^[:alnum:]_])(?:sk-[A-Za-z0-9_-]{8,}|sk_(?:live|test|prod)_[A-Za-z0-9_-]{8,})/ ||
      /(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{8,}/ ||
      /xox[baprs]-[A-Za-z0-9-]{8,}/ ||
      /glpat-[A-Za-z0-9_-]{8,}/ ||
      /AIza[0-9A-Za-z_-]{16,}/ ||
      /(?:AKIA|ASIA)[0-9A-Z]{16}/ ||
      /[[:alnum:]_.-]*(?:token|secret|password|api[_-]?key)["\x27]*\s*[:=]/i
    ) {
      # Redact the complete line. This remains fail-closed for shell-escaped
      # spaces and escaped quotes where value-only regular expressions can
      # otherwise leave a credential suffix in a public artifact.
      print "<redacted>\n";
      next;
    }
    s{[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}}{<redacted-email>}g;
    s{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}}{<redacted-uuid>}g;
    print;
  '
}
