import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Что происходит при нажатии на телефон, почту или ссылку в карточке.
///
/// Поведение телефона разное на разных системах, и это не прихоть:
/// - на **Android** телефон есть, поэтому открывается набор номера — там это
///   самое короткое действие;
/// - на **Windows** звонить нечем, и попытка открыть `tel:` в лучшем случае
///   покажет диалог выбора программы. Полезное действие здесь одно —
///   положить номер в буфер, чтобы перенести его в мессенджер или телефон.
class ContactActions {
  ContactActions._();

  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Приводит номер к виду, пригодному для набора: только цифры и ведущий +.
  static String normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final plus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return plus ? '+$digits' : digits;
  }

  /// Результат действия по номеру — чтобы экран знал, что сказать человеку.
  static Future<PhoneActionResult> phone(String raw) async {
    final number = normalizePhone(raw);
    if (number.isEmpty) return PhoneActionResult.invalid;

    if (isMobile) {
      final uri = Uri(scheme: 'tel', path: number);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return PhoneActionResult.dialed;
      }
    }
    await Clipboard.setData(ClipboardData(text: number));
    return PhoneActionResult.copied;
  }

  /// Открывает почтовый ящик с заполненным получателем.
  static Future<bool> email(String address) async {
    final value = address.trim();
    if (value.isEmpty || !value.contains('@')) return false;
    final uri = Uri(scheme: 'mailto', path: value);
    return _open(uri);
  }

  /// Ссылка на соцсеть.
  ///
  /// Люди пишут её как придётся: `@wesi`, `t.me/wesi`, `https://…`. Приводим
  /// к рабочему адресу, иначе «рабочая ссылка» окажется рабочей только у
  /// того, кто вводил её аккуратно.
  static Uri? socialUri(String network, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.tryParse(value);
    }

    final handle = value.startsWith('@') ? value.substring(1) : value;
    if (handle.isEmpty) return null;

    final base = switch (network.toLowerCase()) {
      'telegram' || 'tg' || 'телеграм' => 'https://t.me/',
      'vk' || 'вк' || 'вконтакте' => 'https://vk.com/',
      'instagram' || 'инстаграм' => 'https://instagram.com/',
      'whatsapp' || 'ватсап' => 'https://wa.me/',
      'github' => 'https://github.com/',
      'linkedin' => 'https://linkedin.com/in/',
      'x' || 'twitter' => 'https://x.com/',
      'youtube' => 'https://youtube.com/@',
      'discord' => 'https://discord.com/users/',
      _ => null,
    };
    if (base == null) {
      // Незнакомая сеть, а значение похоже на адрес — пробуем как есть.
      return value.contains('.') ? Uri.tryParse('https://$value') : null;
    }
    // Для WhatsApp в ссылке нужен номер без плюса и знаков.
    if (base == 'https://wa.me/') {
      final digits = handle.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? null : Uri.parse('$base$digits');
    }
    return Uri.tryParse('$base$handle');
  }

  static Future<bool> social(String network, String raw) async {
    final uri = socialUri(network, raw);
    if (uri == null) return false;
    return _open(uri);
  }

  static Future<bool> _open(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Сети, которые предлагаются при заполнении карточки.
  static const List<String> knownNetworks = [
    'Telegram',
    'VK',
    'WhatsApp',
    'Instagram',
    'GitHub',
    'LinkedIn',
    'X',
    'YouTube',
    'Discord',
  ];
}

enum PhoneActionResult {
  /// Открыли набор номера (телефон).
  dialed,

  /// Положили в буфер обмена (компьютер).
  copied,

  /// В строке не нашлось номера.
  invalid,
}
