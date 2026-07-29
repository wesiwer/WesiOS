import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction_model.dart';
import 'forecast_engine.dart';

/// Именованный пользовательский сценарий «Что если?».
///
/// [WhatIfScenario] из движка живёт ровно один вызов `generate` и исчезает.
/// Здесь он получает имя и сохраняется, чтобы набор своих сценариев можно
/// было накопить, сравнить друг с другом на одном графике и вернуться к ним
/// завтра.
class WhatIfPreset {
  final String id;
  final String name;
  final WhatIfScenario scenario;
  final DateTime createdAt;

  const WhatIfPreset({
    required this.id,
    required this.name,
    required this.scenario,
    required this.createdAt,
  });

  WhatIfPreset copyWith({String? name, WhatIfScenario? scenario}) =>
      WhatIfPreset(
        id: id,
        name: name ?? this.name,
        scenario: scenario ?? this.scenario,
        createdAt: createdAt,
      );

  /// Короткое человеческое описание — что именно этот сценарий меняет.
  /// Нужно на карточке: имя вроде «План Б» само по себе ничего не говорит.
  String summary(String symbol, bool ru) {
    final parts = <String>[];
    for (final e in scenario.events) {
      final sign = e.type == TransactionType.income ? '+' : '−';
      parts.add('${e.title}: $sign$symbol${e.amount.toStringAsFixed(0)}');
    }
    final inc = ((scenario.incomeMultiplier - 1) * 100).round();
    final exp = ((scenario.expenseMultiplier - 1) * 100).round();
    if (inc != 0) {
      parts.add(
          '${ru ? 'доходы' : 'income'} ${inc > 0 ? '+' : ''}$inc%');
    }
    if (exp != 0) {
      parts.add(
          '${ru ? 'расходы' : 'expenses'} ${exp > 0 ? '+' : ''}$exp%');
    }
    if (parts.isEmpty) return ru ? 'Без изменений' : 'No changes';
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'incomeMultiplier': scenario.incomeMultiplier,
        'expenseMultiplier': scenario.expenseMultiplier,
        'events': scenario.events
            .map((e) => {
                  'title': e.title,
                  'amount': e.amount,
                  'type': e.type == TransactionType.income ? 'income' : 'expense',
                  // Храним смещение в днях, а не абсолютную дату: сценарий
                  // «крупная закупка через 2 недели» должен оставаться
                  // осмысленным и через месяц, а прибитая дата к тому времени
                  // уже уехала бы в прошлое и просто выпала из прогноза.
                  'dayOffset': _offsetOf(e.date),
                })
            .toList(),
      };

  static int _offsetOf(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    return diff < 1 ? 1 : diff;
  }

  static WhatIfPreset? fromJson(Map<String, dynamic> json) {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final events = <WhatIfEvent>[];
      for (final raw in (json['events'] as List? ?? const [])) {
        final e = Map<String, dynamic>.from(raw as Map);
        final offset = (e['dayOffset'] as num?)?.toInt() ?? 1;
        events.add(WhatIfEvent(
          title: e['title'] as String? ?? '',
          amount: (e['amount'] as num?)?.toDouble() ?? 0,
          type: e['type'] == 'income'
              ? TransactionType.income
              : TransactionType.expense,
          date: today.add(Duration(days: offset)),
        ));
      }
      return WhatIfPreset(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        scenario: WhatIfScenario(
          events: events,
          incomeMultiplier:
              (json['incomeMultiplier'] as num?)?.toDouble() ?? 1.0,
          expenseMultiplier:
              (json['expenseMultiplier'] as num?)?.toDouble() ?? 1.0,
        ),
      );
    } catch (_) {
      // Битую запись молча пропускаем — один испорченный сценарий не должен
      // ронять весь список.
      return null;
    }
  }
}

/// Хранилище пользовательских сценариев песочницы.
///
/// Нетипизированный Hive-бокс с JSON-строками, а не `TypeAdapter`: сценарий —
/// конфигурация, а не бизнес-модель, и его форма будет меняться. JSON
/// переживает добавление поля без миграции адаптера и без нового typeId.
class WhatIfStore {
  static const String _boxName = 'wesios_whatif';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box? _box;

  static Future<Box> get _presetsBox async {
    _box ??= await Hive.openBox(_boxName);
    return _box!;
  }

  static Future<List<WhatIfPreset>> getAll() async {
    final box = await _presetsBox;
    final out = <WhatIfPreset>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! String) continue;
      try {
        final preset =
            WhatIfPreset.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (preset != null) out.add(preset);
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  static Future<void> save(WhatIfPreset preset) async {
    final box = await _presetsBox;
    await box.put(preset.id, jsonEncode(preset.toJson()));
    revision.value++;
  }

  static Future<void> delete(String id) async {
    final box = await _presetsBox;
    await box.delete(id);
    revision.value++;
  }

  static Future<void> clear() async {
    final box = await _presetsBox;
    await box.clear();
    revision.value++;
  }
}
