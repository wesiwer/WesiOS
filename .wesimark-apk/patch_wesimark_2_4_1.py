#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
printer = root / 'lib/data/repo/printer_service.dart'
pubspec = root / 'pubspec.yaml'

s = printer.read_text(encoding='utf-8')
pattern = re.compile(
    r"      if \(isVsonTransport && !isBonded\) \{\n"
    r"        await _triggerVsonSecurityPairing\(device\);\n"
    r"        if \(!isBonded\) await _ensureBond\(device, required: true\);\n"
    r"        await _ensureConnectedAfterBond\(device\);\n"
    r"        await _negotiateMtu\(device\);\n"
    r"        _write = await _findWriteCharacteristic\(device\);\n"
    r"      \}\n"
)
replacement = (
    "      if (isVsonTransport && !isBonded) {\n"
    "        await _primeVsonSecurityForPairing(device);\n"
    "        await _ensureBond(device, required: true);\n"
    "        await _restoreVsonAfterBond(device);\n"
    "      }\n"
)
s, count = pattern.subn(replacement, s)
if count != 3:
    raise SystemExit(f'Expected 3 VSON pairing blocks, found {count}')

old_comment = '''      // Сначала делаем service discovery. iLabel показывает системный pairing\n      // именно при доступе к защищённым AE02/AE01, а не просто на GATT-connect.\n      // Поэтому для WP9520 сначала повторяем этот security path, и лишь затем\n      // используем явный createBond как резервный путь.\n'''
s = s.replace(old_comment, '''      // Сначала подтверждаем, что это действительно WP9520 по AE30/AE01.\n      // После этого pairing для него становится обязательным этапом подключения.\n''')

start_marker = '  /// Fallback, повторяющий поведение iLabel: защищённый CCCD/notify на'
end_marker = '  Future<void> _ensureConnectedAfterBond'
start = s.find(start_marker)
end = s.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('Old VSON pairing helper not found')
helper = '''  /// Коротко повторяем security path iLabel перед явным Android bond.\n  ///\n  /// Здесь только инициируется доступ к защищённым AE02/AE01; сразу после\n  /// возврата вызывается createBond(), без прежнего ожидания до 60 секунд.\n  Future<void> _primeVsonSecurityForPairing(BluetoothDevice device) async {\n    if (isBonded) return;\n    _set(PrinterState.connecting, 'Открываем системное сопряжение…');\n    _note('VSON security prime: AE02 notify → AE01 hello → createBond');\n\n    BluetoothCharacteristic? notify;\n    BluetoothCharacteristic? write;\n    try {\n      for (final service in await device.discoverServices()) {\n        if (service.serviceUuid.str128.toLowerCase() != _vsonServiceUuid) {\n          continue;\n        }\n        for (final c in service.characteristics) {\n          final id = c.uuid.str128.toLowerCase();\n          if (id == _vsonNotifyUuid) notify = c;\n          if (id == _vsonWriteUuid) write = c;\n        }\n      }\n\n      if (notify != null) {\n        try {\n          await notify.setNotifyValue(true).timeout(const Duration(seconds: 3));\n          _note('AE02 security prime: notify включён');\n        } catch (e) {\n          _note('AE02 security prime: $e');\n        }\n      }\n\n      if (!isBonded && write != null) {\n        try {\n          await write.write(Vson.hello, withoutResponse: true)\n              .timeout(const Duration(seconds: 3));\n          _note('AE01 security prime: hello отправлен');\n        } catch (e) {\n          _note('AE01 security prime: $e');\n        }\n      }\n    } catch (e) {\n      _note('VSON security prime не завершён: $e');\n    }\n    await Future<void>.delayed(const Duration(milliseconds: 250));\n  }\n\n  /// После BOND_BONDED GATT может кратко оборваться. Восстанавливаем связь,\n  /// заново запрашиваем MTU и повторно получаем AE30/AE01.\n  Future<void> _restoreVsonAfterBond(BluetoothDevice device) async {\n    await _ensureConnectedAfterBond(device);\n    await _negotiateMtu(device);\n    _write = await _findWriteCharacteristic(device);\n    if (_write == null || !isVsonTransport) {\n      throw StateError('WP9520: AE30/AE01 пропал после сопряжения');\n    }\n    _note('WP9520: AE30/AE01 повторно открыт после BOND_BONDED');\n  }\n\n'''
s = s[:start] + helper + s[end:]
printer.write_text(s, encoding='utf-8')

p = pubspec.read_text(encoding='utf-8')
if 'version: 2.4.0+14' not in p:
    raise SystemExit('Unexpected source version')
pubspec.write_text(p.replace('version: 2.4.0+14', 'version: 2.4.1+15'), encoding='utf-8')

print('WesiMark 2.4.1+15 pairing patch applied')
