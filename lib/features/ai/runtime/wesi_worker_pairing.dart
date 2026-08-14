import 'dart:convert';

class WesiWorkerPairingTicket {
  static const scheme = 'wesios';
  static const host = 'worker-pair';

  final String ticketId;
  final String workerId;
  final String workerName;
  final String deviceFingerprint;
  final String nonce;
  final DateTime expiresAt;
  final String? lanHint;

  const WesiWorkerPairingTicket({
    required this.ticketId,
    required this.workerId,
    required this.workerName,
    required this.deviceFingerprint,
    required this.nonce,
    required this.expiresAt,
    this.lanHint,
  });

  bool get expired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  Uri toUri() => Uri(
        scheme: scheme,
        host: host,
        queryParameters: <String, String>{
          'v': '1',
          'ticket': ticketId,
          'worker': workerId,
          'name': base64Url.encode(utf8.encode(workerName)).replaceAll('=', ''),
          'fp': deviceFingerprint,
          'nonce': nonce,
          'exp': expiresAt.toUtc().millisecondsSinceEpoch.toString(),
          if (lanHint != null && lanHint!.isNotEmpty) 'lan': lanHint!,
        },
      );

  factory WesiWorkerPairingTicket.fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != host || uri.queryParameters['v'] != '1') {
      throw const FormatException('Некорректный QR Wesi Worker');
    }
    final ticket = '${uri.queryParameters['ticket'] ?? ''}'.trim();
    final worker = '${uri.queryParameters['worker'] ?? ''}'.trim();
    final fingerprint = '${uri.queryParameters['fp'] ?? ''}'.trim();
    final nonce = '${uri.queryParameters['nonce'] ?? ''}'.trim();
    final expRaw = int.tryParse('${uri.queryParameters['exp'] ?? ''}');
    final encodedName = '${uri.queryParameters['name'] ?? ''}'.trim();
    if (ticket.isEmpty || worker.isEmpty || fingerprint.isEmpty || nonce.isEmpty || expRaw == null || encodedName.isEmpty) {
      throw const FormatException('QR Wesi Worker повреждён');
    }
    String name;
    try {
      final padding = '=' * ((4 - encodedName.length % 4) % 4);
      name = utf8.decode(base64Url.decode(encodedName + padding));
    } catch (_) {
      throw const FormatException('QR Wesi Worker повреждён');
    }
    final parsed = WesiWorkerPairingTicket(
      ticketId: ticket,
      workerId: worker,
      workerName: name,
      deviceFingerprint: fingerprint,
      nonce: nonce,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expRaw, isUtc: true),
      lanHint: uri.queryParameters['lan'],
    );
    if (parsed.expired) throw const FormatException('QR Wesi Worker уже истёк');
    return parsed;
  }
}

class WesiPairedWorker {
  final String workerId;
  final String name;
  final String deviceFingerprint;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;

  const WesiPairedWorker({
    required this.workerId,
    required this.name,
    required this.deviceFingerprint,
    required this.pairedAt,
    this.lastSeenAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workerId': workerId,
        'name': name,
        'deviceFingerprint': deviceFingerprint,
        'pairedAt': pairedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
      };
}
