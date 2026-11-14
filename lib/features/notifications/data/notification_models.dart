import 'package:equatable/equatable.dart';

import '../../../core/network/api_payload.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_models.dart';

/// The delivery channels the backend stores in `type` when the record is a
/// plain channel dispatch. Anything else in `type` is an event name (e.g.
/// `recipient_topup_decision`) from a push payload.
const _channels = {'email', 'sms', 'push', 'in_app', 'inapp'};

/// One entry from GET /api/v1/notifications. These records are created by the
/// backend when it dispatches a push (or email/SMS fallback), so a row may be
/// as thin as `{type: 'push', message: '...'}` or carry the full FCM data
/// payload (`eventType`, `decisionId`, `amount`, `currency`, `senderName`,
/// `serviceType`, `selectedChoice`, …). The backend stores delivery state
/// (`pending`/`sent`/`failed`) but no read flag — read state is overlaid
/// locally per user.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.channel,
    required this.status,
    required this.createdAt,
    this.eventType,
    this.kind = 'general',
    this.data = const <String, dynamic>{},
    this.isRead = false,
    this.userId,
    this.mergedIds = const <String>{},
  });

  final String id;
  final String title;
  final String message;

  /// Delivery channel: `email`, `sms`, `push`, `in_app`.
  final String channel;

  /// Delivery status from the server (`pending`, `sent`, `failed`).
  final String status;
  final DateTime createdAt;

  /// Push event name when the row carries one (`recipient_topup_decision`,
  /// `recipient_topup_resolved`, …).
  final String? eventType;

  /// Presentation category: `decision`, `resolved`, `airtime`, `data`,
  /// `order`, `wallet`, `security`, `promo`, `general`.
  final String kind;

  /// Structured push payload fields (decisionId, topupOrderId, amount,
  /// currency, senderName, serviceType, …) for deep links and rich display.
  final Map<String, dynamic> data;

  /// Local-only read flag merged in by the provider.
  final bool isRead;

  /// Optional owner identifier returned by the backend (`userId`, `recipient`, etc.).
  final String? userId;

  /// All raw notification IDs represented by this card (including duplicates
  /// merged across delivery channels within the deduplication window).
  final Set<String> mergedIds;

  /// Whether this notification is waiting on the recipient's choice.
  bool get needsAction => kind == 'decision';

  /// Returns true if this notification is addressed to [user] or is unscoped.
  bool belongsToUser(UserProfile? user) {
    final rawTarget = userId?.trim() ?? '';
    if (rawTarget.isEmpty || user == null) return true;
    final uid = user.id.trim().toLowerCase();
    final email = user.email.trim().toLowerCase();
    final phone = user.phoneNumber.trim();
    final username = user.username.trim().toLowerCase();
    if (uid.isEmpty && email.isEmpty && phone.isEmpty && username.isEmpty) {
      return true;
    }

    final target = rawTarget.toLowerCase();
    if (target == uid && uid.isNotEmpty) return true;
    if (target == email && email.isNotEmpty) return true;
    if (target == username && username.isNotEmpty) return true;

    if (!target.contains('@')) {
      if (_samePhone(target, phone)) return true;
      if (!username.contains('@') && _samePhone(target, username)) return true;
    }
    return false;
  }

  static bool _samePhone(String a, String b) {
    final da = a.replaceAll(RegExp(r'\D'), '');
    final db = b.replaceAll(RegExp(r'\D'), '');
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    if (da.length >= 9 && db.length >= 9) {
      return da.substring(da.length - 9) == db.substring(db.length - 9);
    }
    return false;
  }

  /// Human-friendly title: server subject, else derived from the event.
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty && t.toLowerCase() != 'notification') return t;
    return switch (kind) {
      'decision' => 'Top-up needs your choice',
      'resolved' => 'Top-up completed',
      'airtime' => 'Airtime top-up',
      'data' => 'Data bundle',
      'order' => 'Order update',
      'wallet' => 'Lida Value',
      'security' => 'Security alert',
      'promo' => 'Offer',
      _ => 'Lidapay',
    };
  }

  /// Human-friendly body: server message, else composed from the payload.
  /// The backend sometimes appends the raw entity JSON to `message`
  /// ("Your profile has been updated successfully. Details: {…}") — that
  /// tail contains password hashes, tokens and base64 blobs, so it is
  /// stripped here and never reaches the UI.
  String get displayMessage {
    final m = _sanitizeMessage(message);
    if (m.isNotEmpty) return m;
    final sender = _str('senderName');
    final amount = _amountLabel();
    final service = _serviceLabel();
    return switch (kind) {
      'decision' when sender != null && amount != null =>
        '$sender sent you $amount $service. Tap to choose where to receive it.',
      'decision' when amount != null =>
        'You received $amount $service. Tap to choose where to receive it.',
      'decision' =>
        'Someone sent you a top-up. Tap to choose where to receive it.',
      'resolved' => 'Your top-up was delivered successfully.',
      _ => '',
    };
  }

  /// Removes embedded JSON objects/arrays and their "Details:" lead-in from
  /// a free-text message. Anything from the first `{`/`[` onward is treated
  /// as machine payload, not prose.
  static String _sanitizeMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    var cut = trimmed.indexOf(RegExp(r'[\{\[]'));
    if (cut < 0) return trimmed;
    if (cut == 0) return '';
    var prose = trimmed.substring(0, cut).trim();
    prose = prose.replaceAll(
      RegExp(r'\s*(details?|payload|data)\s*[:\-]?\s*$', caseSensitive: false),
      '',
    );
    return prose.trim();
  }

  String? _str(String key) {
    final v = data[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  String? _amountLabel() {
    final raw = data['amount'];
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse('$raw'.replaceAll(',', ''));
    if (amount == null) return null;
    final currency = _str('currency') ?? _str('currencyCode') ?? 'GHS';
    return Formatters.money(amount, currency);
  }

  String _serviceLabel() {
    final service = (_str('serviceType') ?? _str('service') ?? '')
        .toUpperCase();
    if (service.contains('DATA') || service.contains('BUNDLE')) return 'data';
    return 'airtime';
  }

  AppNotification copyWith({bool? isRead, Set<String>? mergedIds}) =>
      AppNotification(
        id: id,
        title: title,
        message: message,
        channel: channel,
        status: status,
        createdAt: createdAt,
        eventType: eventType,
        kind: kind,
        data: data,
        isRead: isRead ?? this.isRead,
        userId: userId,
        mergedIds: mergedIds ?? this.mergedIds,
      );

  static String _extractId(Map<String, dynamic> pool) {
    for (final key in const ['_id', 'id', 'notificationId', 'ref']) {
      final value = pool[key];
      if (value == null) continue;
      if (value is Map) {
        final oid = value[r'$oid']?.toString().trim() ?? '';
        if (oid.isNotEmpty && oid != 'null') return oid;
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  factory AppNotification.fromApiJson(Map<String, dynamic> json) {
    final pool = payloadPool(json);
    final rawId = _extractId(pool);

    // `type` is ambiguous: channel dispatches use email/sms/push, but push
    // records may store the event name there. Split it accordingly.
    final rawType =
        stringField(pool, const ['type', 'channel', 'medium']) ?? '';
    final isChannel = _channels.contains(rawType.toLowerCase());
    final channel = isChannel
        ? (rawType.toLowerCase() == 'inapp' ? 'in_app' : rawType.toLowerCase())
        : 'push';
    final eventType =
        stringField(pool, const ['eventType', 'event', 'notificationType']) ??
        (isChannel || rawType.isEmpty ? null : rawType);

    // Structured payload: nested `data`/`payload` map plus top-level extras.
    final data = <String, dynamic>{};
    for (final key in const ['data', 'payload', 'meta', 'metadata']) {
      final inner = pool[key];
      if (inner is Map) data.addAll(Map<String, dynamic>.from(inner));
    }
    for (final key in const [
      'decisionId',
      'topupOrderId',
      'serviceType',
      'amount',
      'currency',
      'senderName',
      'recipientPhone',
      'selectedChoice',
      'finalDisposition',
      'expiresAt',
    ]) {
      if (pool[key] != null) data.putIfAbsent(key, () => pool[key]);
    }

    final title =
        stringField(pool, const ['subject', 'title', 'heading', 'name']) ?? '';
    final rawMessage =
        stringField(pool, const [
          'message',
          'body',
          'text',
          'description',
          'content',
        ]) ??
        '';
    final message = _sanitizeMessage(rawMessage);
    final createdAt =
        dateField(pool, const [
          'createdAt',
          'created_at',
          'date',
          'timestamp',
          'sentAt',
        ]) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final id = rawId.isNotEmpty
        ? rawId
        : 'notif_${channel}_${createdAt.millisecondsSinceEpoch}_${title.hashCode}_${message.hashCode}';
    final userId =
        stringField(pool, const ['userId', 'recipientId', 'recipient', 'to']) ??
        stringField(data, const [
          'userId',
          'recipientId',
          'recipient',
          'recipientPhone',
        ]);
    final status = stringField(pool, const ['status', 'state']) ?? 'sent';

    return AppNotification(
      id: id,
      title: title,
      message: message,
      channel: channel,
      status: status,
      createdAt: createdAt,
      eventType: eventType,
      kind: _kindOf(eventType, title, message, data),
      data: data,
      isRead:
          pool['isRead'] == true ||
          pool['read'] == true ||
          pool['readAt'] != null ||
          status.toLowerCase() == 'read',
      userId: userId,
    );
  }

  static String _kindOf(
    String? eventType,
    String title,
    String message,
    Map<String, dynamic> data,
  ) {
    final cleanMessage = _sanitizeMessage(message);
    final text = '$eventType $title $cleanMessage'.toUpperCase();
    final event = (eventType ?? '').toUpperCase();

    if (event.contains('RESOLVED') ||
        data['selectedChoice'] != null ||
        data['finalDisposition'] != null) {
      return 'resolved';
    }
    if (event.contains('DECISION') ||
        data['decisionId'] != null ||
        text.contains('CHOOSE WHERE')) {
      return 'decision';
    }

    // Whole-word matching only — `contains('DATA')` misfires on "UPDATED",
    // `contains('POINT')` on "APPOINTED", etc. Exclude trailing colon so
    // data URIs (`data:image/...`) never match.
    bool hasWord(String word) => RegExp(
      '(^|[^A-Z])$word([^A-Z:]|\$)',
    ).hasMatch(text);

    // Security & profile updates take precedence over telecom keyword guessing.
    if (hasWord('SECURITY') ||
        text.contains('SIGNED IN') ||
        hasWord('PASSWORD') ||
        (hasWord('PROFILE') && hasWord('UPDATED'))) {
      return 'security';
    }

    if (hasWord('AIRTIME') || text.contains('TOP-UP')) return 'airtime';
    if (hasWord('DATA') || hasWord('BUNDLE')) return 'data';
    if (hasWord('ORDER') || hasWord('SHOP') || hasWord('SHIPPED')) {
      return 'order';
    }
    if (hasWord('VALUE') || hasWord('POINT') || hasWord('WALLET')) {
      return 'wallet';
    }
    if (hasWord('DEAL') || hasWord('PROMO') || text.contains('%')) {
      return 'promo';
    }
    return 'general';
  }

  @override
  List<Object?> get props => [
    id,
    title,
    message,
    channel,
    status,
    eventType,
    kind,
    isRead,
    userId,
    mergedIds,
  ];
}
