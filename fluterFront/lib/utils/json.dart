/// Tolerant numeric parsing for API payloads.
///
/// node-postgres returns NUMERIC/BIGINT columns as strings. Dart's `as num` casts throw instead and
/// blank the page in release builds — always go through these helpers for
/// numbers coming from the backend.
num toNum(dynamic v, [num fallback = 0]) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

num? toNumOrNull(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}
