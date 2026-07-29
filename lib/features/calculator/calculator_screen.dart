import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';
import '../../core/theme/app_theme.dart';

/// Глобальный оверлей калькулятора.
///
/// Калькулятор живёт поверх всего дерева (рядом с WindowControls в `app.dart`),
/// а не отдельным роутом — поэтому закреплённый (pinned) калькулятор
/// переживает переключение вкладок в HomeScreen.
class CalculatorOverlay {
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  static void show() => visible.value = true;
  static void hide() => visible.value = false;
  static void toggle() => visible.value = !visible.value;
}

class CalculatorScreen extends StatefulWidget {
  /// true — виджет отрисован как глобальный оверлей, а не как route.
  final bool asOverlay;

  const CalculatorScreen({super.key, this.asOverlay = false});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

/// Одна завершённая операция в истории калькулятора.
class _CalcEntry {
  final String expression;
  final String result;
  const _CalcEntry({required this.expression, required this.result});
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = '';
  String _result = '0';
  final FocusNode _focusNode = FocusNode();

  /// true — последнее действие было «=». Следующий оператор продолжит счёт
  /// от результата, а следующая цифра начнёт новое вычисление.
  bool _justEvaluated = false;

  static const int _historyLimit = 50;
  final List<_CalcEntry> _history = [];
  bool _showHistory = false;

  bool _pinned = false;
  bool _showBlur = true;
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onPressed(String value) {
    setState(() {
      if (value == 'C' || value == 'c') {
        _expression = '';
        _result = '0';
        _justEvaluated = false;
      } else if (value == 'Delete' || value == 'DEL') {
        _expression = '';
        _result = '0';
        _justEvaluated = false;
      } else if (value == '=' || value == 'Enter') {
        _calculate();
      } else if (value == '⌫' || value == 'Backspace') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
        _justEvaluated = false;
      } else if (_isValidInput(value)) {
        // Продолжение счёта от результата: после «=» набранный оператор
        // должен применяться К РЕЗУЛЬТАТУ, а не дописываться к старому
        // выражению. Раньше «10+5 =» давало 15, а следующее «*2» превращало
        // строку в «10+5*2» — по приоритету операций получалось 20 вместо
        // ожидаемых 30. Теперь после «=» выражение начинается с результата.
        if (_justEvaluated) {
          if (_isOperator(value)) {
            _expression = '$_result$value';
          } else {
            // Новая цифра после «=» — это начало нового вычисления.
            _expression = value;
            _result = '0';
          }
          _justEvaluated = false;
        } else {
          _expression += value;
        }
      }
    });
  }

  bool _isValidInput(String value) {
    const valid = '0123456789.+-*/()^%';
    return valid.contains(value);
  }

  static bool _isOperator(String v) => '+-*/^%'.contains(v) && v.length == 1;

  void _calculate() {
    if (_expression.isEmpty) return;
    try {
      final p = Parser();
      final exp = p.parse(_expression);
      final cm = ContextModel();
      final eval = exp.evaluate(EvaluationType.REAL, cm);
      final formatted =
          eval == eval.toInt() ? eval.toInt().toString() : eval.toString();
      // Каждое «=» — отдельная запись в истории, а не продолжение прошлой.
      _history.insert(0, _CalcEntry(expression: _expression, result: formatted));
      if (_history.length > _historyLimit) _history.removeLast();
      _result = formatted;
      _justEvaluated = true;
    } catch (_) {
      _result = 'Error';
      _justEvaluated = false;
    }
  }

  /// LogicalKeyboardKey не имеет primitive equality → const-мапа невозможна.
  /// static final: строится один раз, а не на каждое нажатие.
  static final Map<LogicalKeyboardKey, String> _numpadMap = {
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
    LogicalKeyboardKey.numpadDecimal: '.',
    LogicalKeyboardKey.numpadAdd: '+',
    LogicalKeyboardKey.numpadSubtract: '-',
    LogicalKeyboardKey.numpadMultiply: '*',
    LogicalKeyboardKey.numpadDivide: '/',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.numpadEqual: '=',
  };

  String? _mapNumpad(LogicalKeyboardKey key) => _numpadMap[key];

  /// Закрытие: в оверлей-режиме прячем оверлей, иначе — обычный pop.
  void _close() {
    if (widget.asOverlay) {
      CalculatorOverlay.hide();
    } else {
      Navigator.pop(context);
    }
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (!_pinned) _close();
      return;
    }
    if (key == LogicalKeyboardKey.delete) {
      _onPressed('Delete');
      return;
    }

    final np = _mapNumpad(key);
    if (np != null) {
      _onPressed(np);
      return;
    }
    if (key == LogicalKeyboardKey.enter) {
      _onPressed('Enter');
    } else if (key == LogicalKeyboardKey.backspace) {
      _onPressed('Backspace');
    } else {
      final char = key.keyLabel;
      if (char.length == 1) _onPressed(char);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = Transform.translate(
      offset: _offset,
      child: Transform.scale(
        scale: _scale,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => _offset += d.delta),
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _pinned
                        ? AppTheme.accentOrange.withOpacity(0.5)
                        : AppTheme.glassBorder,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.45),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        color: AppTheme.surface,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            const Text(
                              'Wesi Calculator',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: _showHistory
                                  ? 'Скрыть историю'
                                  : 'История вычислений',
                              icon: Icon(
                                Icons.history,
                                size: 18,
                                color: _showHistory
                                    ? AppTheme.accentOrange
                                    : AppTheme.textMuted,
                              ),
                              onPressed: () =>
                                  setState(() => _showHistory = !_showHistory),
                            ),
                            IconButton(
                              tooltip: _showBlur ? 'Убрать блюр' : 'Включить блюр',
                              icon: Icon(
                                _showBlur ? Icons.blur_on : Icons.blur_off,
                                size: 18,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () =>
                                  setState(() => _showBlur = !_showBlur),
                            ),
                            IconButton(
                              tooltip: _pinned ? 'Открепить' : 'Закрепить',
                              icon: Icon(
                                _pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: _pinned
                                    ? AppTheme.accentOrange
                                    : AppTheme.textMuted,
                              ),
                              onPressed: () =>
                                  setState(() => _pinned = !_pinned),
                            ),
                            IconButton(
                              tooltip: 'Уменьшить',
                              icon: const Icon(Icons.remove, size: 18,
                                  color: AppTheme.textMuted),
                              onPressed: () => setState(
                                  () => _scale = (_scale - 0.1).clamp(0.7, 1.4)),
                            ),
                            IconButton(
                              tooltip: 'Увеличить',
                              icon: const Icon(Icons.add, size: 18,
                                  color: AppTheme.textMuted),
                              onPressed: () => setState(
                                  () => _scale = (_scale + 0.1).clamp(0.7, 1.4)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _close,
                            ),
                          ],
                        ),
                      ),
                      // Display
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _expression,
                              style: const TextStyle(
                                  fontSize: 20, color: AppTheme.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _result,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_showHistory) _historyPanel(),
                      // Keys
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: Column(
                          children: [
                            _row(['C', 'DEL', '(', ')', '⌫']),
                            const SizedBox(height: 8),
                            _row(['7', '8', '9', '/']),
                            const SizedBox(height: 8),
                            _row(['4', '5', '6', '*']),
                            const SizedBox(height: 8),
                            _row(['1', '2', '3', '-']),
                            const SizedBox(height: 8),
                            _row(['0', '.', '=', '+']),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Resize за угол — пропорционально, тот же clamp что и у +/−
              Positioned(right: 2, bottom: 2, child: _resizeHandle()),
            ],
          ),
        ),
      ),
    );

    final content = Stack(
      children: [
        // Закреплённый калькулятор не перехватывает клики по приложению —
        // backdrop рисуем только когда он не закреплён.
        if (!_pinned)
          GestureDetector(
            onTap: _close,
            // Настоящее размытие фона, а не просто затемнение.
            //
            // Плавность даёт TweenAnimationBuilder: sigma растёт от 0 до
            // целевого значения за 260 мс. Резкое включение BackdropFilter
            // на полную силу — это один тяжёлый кадр, который и читался как
            // «блюр с зависанием»; постепенный рост распределяет нагрузку и
            // выглядит как плавное появление.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _showBlur ? 14 : 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, sigma, _) {
                final backdrop = Container(
                  color: Colors.black.withOpacity(_showBlur ? 0.35 : 0.0),
                );
                if (sigma <= 0.01) return backdrop;
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: backdrop,
                );
              },
            ),
          ),
        Center(child: panel),
      ],
    );

    final listener = KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: content,
    );

    if (widget.asOverlay) {
      return Material(type: MaterialType.transparency, child: listener);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: listener,
    );
  }

  /// История вычислений: каждое «=» — отдельная строка, а не продолжение
  /// прошлой. Тап по строке возвращает её результат в текущий расчёт.
  Widget _historyPanel() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: _history.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('История пуста',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(
                    children: [
                      const Text('История',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMuted)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(_history.clear),
                        child: const Text('Очистить',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.accentOrange)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _history.length,
                    itemBuilder: (context, i) {
                      final e = _history[i];
                      return InkWell(
                        onTap: () => setState(() {
                          _expression = e.result;
                          _result = e.result;
                          _justEvaluated = true;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.expression,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '= ${e.result}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _resizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          // Усредняем смещение по осям — пропорции панели не плывут
          final delta = (d.delta.dx + d.delta.dy) / 2;
          _scale = (_scale + delta / 300).clamp(0.7, 1.4);
        }),
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.all(3),
          color: Colors.transparent,
          child: Icon(
            Icons.open_in_full,
            size: 12,
            color: AppTheme.textMuted.withOpacity(0.8),
          ),
        ),
      ),
    );
  }

  Widget _row(List<String> keys) {
    return Row(
      children: keys
          .map((t) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _btn(t),
                ),
              ))
          .toList(),
    );
  }

  Widget _btn(String text) {
    Color? color;
    if (text == 'C' || text == 'DEL') {
      color = AppTheme.accentRed;
    } else if (text == '=') {
      color = AppTheme.accentGreen;
    } else if (['/', '*', '-', '+', '⌫'].contains(text)) {
      color = AppTheme.accentOrange;
    }

    return GestureDetector(
      onTap: () => _onPressed(text),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color != null ? color.withOpacity(0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color != null ? color.withOpacity(0.3) : AppTheme.glassBorder,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
