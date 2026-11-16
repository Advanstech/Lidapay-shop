/// Single source of truth for Ghana's domestic (One4All/Prymo) network codes
/// and number-prefix detection. Codes follow the backend Swagger: 1 AirtelTigo,
/// 3 Glo, 4 MTN, 6 Telecel, 8 Busy, 9 Surfline (0 = provider auto-detect).
///
/// Detection is deterministic and works offline, so a slow or failed operator
/// lookup can never leave a number on the wrong network.
class GhanaNetworks {
  GhanaNetworks._();

  static const mtn = '4';
  static const mtnYellow = '13';
  static const telecel = '6';
  static const airteltigo = '1';
  static const glo = '3';

  /// Local 3-digit prefix (`0XX`) → brand.
  static const _prefixBrands = <String, String>{
    '024': 'MTN',
    '025': 'MTN',
    '053': 'MTN',
    '054': 'MTN',
    '055': 'MTN',
    '059': 'MTN',
    '020': 'Telecel',
    '050': 'Telecel',
    '026': 'AirtelTigo',
    '027': 'AirtelTigo',
    '056': 'AirtelTigo',
    '057': 'AirtelTigo',
    '023': 'Glo',
  };

  static const brandToCode = <String, String>{
    'MTN': mtn,
    'MTN YELLOW': mtnYellow,
    'TELECEL': telecel,
    'VODAFONE': telecel,
    'AIRTELTIGO': airteltigo,
    'AIRTEL': airteltigo,
    'TIGO': airteltigo,
    'GLO': glo,
    'BUSY': '8',
    'SURFLINE': '9',
  };

  /// Normalises any typed form (`0244…`, `244…`, `233244…`, `+233 244…`) to
  /// the local 10-digit `0XXXXXXXXX` shape, or as much of it as was typed.
  static String localDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00233')) d = d.substring(5);
    // Only treat 233 as the country code once the number is long enough to
    // be international (12 digits) — a short "233…" is a local 23x number.
    if (d.startsWith('233') && d.length >= 12) {
      d = d.substring(3);
    } else if (d.startsWith('233') && d.length > 10) {
      d = d.substring(3);
    }
    if (d.isNotEmpty && !d.startsWith('0')) d = '0$d';
    return d;
  }

  static String? brandForNumber(String raw) {
    final local = localDigits(raw);
    if (local.length < 3) return null;
    return _prefixBrands[local.substring(0, 3)];
  }

  /// Prymo code for the number's prefix, or null when unknown/incomplete.
  static String? codeForNumber(String raw) {
    final brand = brandForNumber(raw);
    return brand == null ? null : brandToCode[brand.toUpperCase()];
  }

  /// Maps a provider operator name ("MTN Ghana", "Vodafone Ghana") to the
  /// One4All/Prymo code. Order matters: the more specific names are tested
  /// first ("MTN Yellow" before "MTN", "AirtelTigo" before "TiGO").
  /// Returns null when nothing matches — callers then send `0` (the
  /// provider's own auto-detect).
  static const _nameOrder = <(String, String)>[
    ('MTN YELLOW', '13'),
    ('MTN', '4'),
    ('AIRTELTIGO', '1'),
    ('AIRTEL', '1'),
    ('TIGO', '5'),
    ('EXPRESSO', '2'),
    ('TELECEL', '6'),
    ('VODAFONE', '6'),
    ('GLO', '3'),
    ('BUSY', '8'),
    ('SURFLINE', '9'),
  ];

  static const codeToName = <String, String>{
    '0': 'Auto Detect',
    '1': 'AirtelTigo',
    '2': 'Expresso',
    '3': 'Glo Ghana',
    '4': 'MTN Ghana',
    '5': 'TiGO',
    '6': 'Telecel Ghana',
    '8': 'Busy',
    '9': 'Surfline',
    '13': 'MTN Yellow',
  };

  static String? nameForCode(String code) => codeToName[code.trim()];

  static String? codeForName(String name) {
    final upper = name.toUpperCase();
    for (final (key, code) in _nameOrder) {
      if (upper.contains(key)) return code;
    }
    return null;
  }
}
