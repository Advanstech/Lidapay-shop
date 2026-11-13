/// Tolerant readers for endpoints whose OpenAPI response schema is empty.
/// This backend wraps payloads inconsistently (`data`, `result`, provider
/// envelopes) and mixes camelCase/Snake_case/PascalCase field names, so every
/// lookup tries an ordered list of candidate keys instead of a fixed model.
Map<String, dynamic> asMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

/// List payload, unwrapping the usual container keys first.
List<Map<String, dynamic>> rowsOf(Object? raw) {
  if (raw is List) {
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    for (final key in const [
      'bundles',
      'items',
      'data',
      'results',
      'records',
      'transactions',
      'products',
      'categories',
      'countries',
      'orders',
      'services',
      'banks',
      'operators',
      'history',
      'lineItems',
      'entries',
    ]) {
      final value = map[key];
      if (value is List) return rowsOf(value);
      if (value is Map) {
        final nested = rowsOf(value);
        if (nested.length != 1 || nested.first != value) return nested;
      }
    }
    return [map];
  }
  return const [];
}

/// Merged one-level view: nested envelope keys first, top level wins.
Map<String, dynamic> payloadPool(Map<String, dynamic> raw) {
  if (raw.isEmpty) return raw;
  final merged = <String, dynamic>{};
  for (final key in const [
    'data',
    'result',
    'response',
    'transaction',
    'order',
    'product',
    'cart',
  ]) {
    final inner = raw[key];
    if (inner is Map) merged.addAll(Map<String, dynamic>.from(inner));
  }
  merged.addAll(raw);
  return merged;
}

String? stringField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return null;
}

double? numberField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(',', '').trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool boolField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == 'true' || text == 'yes' || text == '1') return true;
      if (text == 'false' || text == 'no' || text == '0') return false;
    }
  }
  return false;
}

DateTime? dateField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    } else if (value is num) {
      final inSeconds = value.toDouble() < 1e10;
      return DateTime.fromMillisecondsSinceEpoch(
        inSeconds ? (value.toDouble() * 1000).round() : value.round(),
      );
    }
  }
  return null;
}
