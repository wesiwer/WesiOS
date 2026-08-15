class WesiSelfDebugRedactor {
  const WesiSelfDebugRedactor();

  String redact(String value) {
    var out = value.replaceAll('\u0000', '');
    out = out.replaceAllMapped(
      RegExp(
        r'(authorization\s*[:=]\s*)(?:bearer|basic)\s+[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );
    out = out.replaceAllMapped(
      RegExp(
        r'\b(password|passwd|token|access[_-]?token|refresh[_-]?token|api[_-]?key|secret|client[_-]?secret)\s*[:=]\s*([^\s,;]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    out = out.replaceAll(
      RegExp(r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b'),
      '[REDACTED_GITHUB_TOKEN]',
    );
    out = out.replaceAll(
      RegExp(r'\bsk-[A-Za-z0-9_-]{16,}\b'),
      '[REDACTED_API_KEY]',
    );
    out = out.replaceAll(
      RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
      '[REDACTED_AWS_KEY]',
    );
    out = out.replaceAll(
      RegExp(
        r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
      ),
      '[REDACTED_JWT]',
    );
    return out;
  }
}
