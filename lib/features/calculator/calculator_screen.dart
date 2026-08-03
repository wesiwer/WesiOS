import 'dart:math' as math;
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

  /// Свёрнут в плавающую полоску (результат + expand / close).
  bool _minimized = false;

  /// false = классический, true = научный (как на скрине).
  bool _scientific = false;

  /// 2nd-функции (asin вместо sin и т.п.).
  bool _second = false;

  /// true = радианы, false = градусы.
  bool _radians = true;

  /// Память калькулятора (mc / m+ / m- / mr).
  double _memory = 0;

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

  // ─── Input handling ───────────────────────────────────────────────────────

  void _onPressed(String value) {
    setState(() {
      switch (value) {
        case 'C':
        case 'AC':
        case 'c':
          _expression = '';
          _result = '0';
          _justEvaluated = false;
          break;
        case 'Delete':
        case 'DEL':
          _expression = '';
          _result = '0';
          _justEvaluated = false;
          break;
        case '=':
        case 'Enter':
          _calculate();
          break;
        case '⌫':
        case 'Backspace':
          if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
          _justEvaluated = false;
          break;
        case '2nd':
          _second = !_second;
          break;
        case 'Rad':
        case 'Deg':
          _radians = !_radians;
          break;
        case 'mc':
          _memory = 0;
          break;
        case 'm+':
          _memory += _currentNumber();
          break;
        case 'm-':
          _memory -= _currentNumber();
          break;
        case 'mr':
          _insertToken(_formatNum(_memory));
          break;
        case '±':
        case '+/-':
          _toggleSign();
          break;
        case 'π':
          _insertToken(math.pi.toString());
          break;
        case 'e':
          _insertToken(math.e.toString());
          break;
        case 'Rand':
          _insertToken(math.Random().nextDouble().toStringAsFixed(8));
          break;
        // Unary / postfix scientific tokens
        case 'x²':
          _insertPostfix('^2');
          break;
        case 'x³':
          _insertPostfix('^3');
          break;
        case 'xʸ':
        case 'x^y':
          _insertPostfix('^');
          break;
        case 'eˣ':
          _insertFunc('exp');
          break;
        case '10ˣ':
          _insertToken('10^');
          break;
        case '1/x':
          _insertFunc('1/');
          break;
        case '√':
        case '²√x':
          _insertFunc('sqrt');
          break;
        case '∛':
        case '³√x':
          _insertToken('^(1/3)');
          break;
        case 'ʸ√x':
          _insertToken('^(1/');
          break;
        case 'ln':
          _insertFunc(_second ? 'exp' : 'ln');
          break;
        case 'log':
        case 'log₁₀':
          _insertFunc('log');
          break;
        case 'x!':
          _insertPostfix('!');
          break;
        case 'sin':
          _insertFunc(_second ? 'asin' : 'sin');
          break;
        case 'cos':
          _insertFunc(_second ? 'acos' : 'cos');
          break;
        case 'tg':
        case 'tan':
          _insertFunc(_second ? 'atan' : 'tan');
          break;
        case 'sh':
        case 'sinh':
          _insertFunc('sinh');
          break;
        case 'ch':
        case 'cosh':
          _insertFunc('cosh');
          break;
        case 'th':
        case 'tanh':
          _insertFunc('tanh');
          break;
        case 'EE':
          _insertToken('*10^');
          break;
        case '%':
          _insertPostfix('%');
          break;
        default:
          if (_isValidInput(value)) {
            if (_justEvaluated) {
              if (_isOperator(value)) {
                _expression = '$_result$value';
              } else {
                _expression = value;
                _result = '0';
              }
              _justEvaluated = false;
            } else {
              _expression += value;
            }
          }
      }
    });
  }

  void _insertToken(String token) {
    if (_justEvaluated) {
      _expression = token;
      _result = '0';
      _justEvaluated = false;
    } else {
      _expression += token;
    }
  }

  void _insertFunc(String name) {
    // 1/ special-case: wrap current or open paren
    if (name == '1/') {
      if (_justEvaluated) {
        _expression = '1/($_result)';
        _justEvaluated = false;
      } else if (_expression.isEmpty) {
        _expression = '1/(';
      } else {
        _expression = '1/($_expression)';
      }
      return;
    }
    if (_justEvaluated) {
      _expression = '$name($_result)';
      _justEvaluated = false;
    } else {
      _expression += '$name(';
    }
  }

  void _insertPostfix(String op) {
    if (_justEvaluated) {
      _expression = '$_result$op';
      _justEvaluated = false;
    } else if (_expression.isEmpty) {
      _expression = '0$op';
    } else {
      _expression += op;
    }
  }

  void _toggleSign() {
    if (_justEvaluated) {
      if (_result.startsWith('-')) {
        _result = _result.substring(1);
      } else if (_result != '0') {
        _result = '-$_result';
      }
      _expression = _result;
      return;
    }
    if (_expression.isEmpty) {
      _expression = '-';
      return;
    }
    // Simple: prepend/remove leading -
    if (_expression.startsWith('-')) {
      _expression = _expression.substring(1);
    } else {
      _expression = '-$_expression';
    }
  }

  double _currentNumber() {
    try {
      final v = double.tryParse(_result.replaceAll(',', '.')) ?? 0;
      return v;
    } catch (_) {
      return 0;
    }
  }

  String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  bool _isValidInput(String value) {
    const valid = '0123456789.+-*/÷×−()^%,';
    return valid.contains(value);
  }

  static bool _isOperator(String v) =>
      '+-*/^%'.contains(v) && v.length == 1;

  // ─── Evaluation ───────────────────────────────────────────────────────────

  void _calculate() {
    if (_expression.isEmpty) return;
    try {
      var expr = _expression
          .replaceAll(',', '.')
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('−', '-');

      // Factorial: simple integer only, replace n! with factorial value
      expr = _expandFactorials(expr);

      // Hyperbolic via rewrite (math_expressions has no sinh/cosh/tanh)
      expr = expr
          .replaceAllMapped(RegExp(r'sinh\(([^)]+)\)'), (m) {
            final x = m[1]!;
            return '((exp($x)-exp(-($x)))/2)';
          })
          .replaceAllMapped(RegExp(r'cosh\(([^)]+)\)'), (m) {
            final x = m[1]!;
            return '((exp($x)+exp(-($x)))/2)';
          })
          .replaceAllMapped(RegExp(r'tanh\(([^)]+)\)'), (m) {
            final x = m[1]!;
            return '((exp($x)-exp(-($x)))/(exp($x)+exp(-($x))))';
          });

      // Percent: n% → (n/100)
      expr = expr.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)%'), (m) {
        return '(${m[1]}/100)';
      });

      // Degree mode: wrap trig args
      if (!_radians) {
        expr = _wrapTrigForDegrees(expr);
      }

      final p = Parser();
      final exp = p.parse(expr);
      final cm = ContextModel();
      // Provide common constants if needed
      cm.bindVariableName('pi', Number(math.pi));
      cm.bindVariableName('e', Number(math.e));

      final eval = exp.evaluate(EvaluationType.REAL, cm);
      final formatted =
          (eval is num && eval == eval.roundToDouble())
              ? eval.round().toString()
              : eval.toString();

      _history.insert(
          0, _CalcEntry(expression: _expression, result: formatted));
      if (_history.length > _historyLimit) _history.removeLast();
      _result = formatted;
      _justEvaluated = true;
    } catch (e) {
      _result = 'Error';
      _justEvaluated = false;
    }
  }

  String _expandFactorials(String expr) {
    return expr.replaceAllMapped(RegExp(r'(\d+)!'), (m) {
      final n = int.tryParse(m[1]!) ?? 0;
      if (n < 0 || n > 20) return m[0]!;
      int f = 1;
      for (int i = 2; i <= n; i++) f *= i;
      return f.toString();
    });
  }

  /// Convert sin(x) → sin(x * pi/180) etc. when in degree mode.
  String _wrapTrigForDegrees(String expr) {
    for (final fn in ['sin', 'cos', 'tan', 'asin', 'acos', 'atan']) {
      expr = expr.replaceAllMapped(RegExp('$fn\\(([^)]+)\\)'), (m) {
        final arg = m[1]!;
        if (fn.startsWith('a')) {
          // inverse: result is in rad → convert to deg
          return '((180/pi)*$fn($arg))';
        }
        return '$fn(($arg)*pi/180)';
      });
    }
    return expr;
  }

  // ─── Keyboard ─────────────────────────────────────────────────────────────

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
    LogicalKeyboardKey.numpadDivide: '÷',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.numpadEqual: '=',
  };

  String? _mapNumpad(LogicalKeyboardKey key) => _numpadMap[key];

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

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Свёрнутая полоска — компактный бар внизу/по центру, без блюра.
    if (_minimized) {
      final bar = _minimizedBar();
      final listener = KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            // Не блокируем клики по приложению, когда свёрнут
            const SizedBox.expand(),
            Positioned(
              left: _offset.dx.clamp(0.0, double.infinity),
              top: _offset.dy.clamp(0.0, double.infinity),
              child: bar,
            ),
          ],
        ),
      );
      if (widget.asOverlay) {
        return Material(type: MaterialType.transparency, child: listener);
      }
      return Scaffold(backgroundColor: Colors.transparent, body: listener);
    }

    final maxW = _scientific ? 420.0 : 360.0;
    final maxH = _scientific ? 720.0 : 600.0;

    final panel = Transform.translate(
      offset: _offset,
      child: Transform.scale(
        scale: _scale,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => _offset += d.delta),
          child: Stack(
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _pinned
                        ? AppTheme.accent.withOpacity(0.5)
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
                      _buildHeader(),
                      _buildDisplay(),
                      if (_showHistory) _historyPanel(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                        child: _scientific
                            ? _scientificKeypad()
                            : _classicKeypad(),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(right: 2, bottom: 2, child: _resizeHandle()),
            ],
          ),
        ),
      ),
    );

    final content = Stack(
      children: [
        if (!_pinned)
          GestureDetector(
            onTap: _close,
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

  /// Плавающая полоска: заголовок / результат + развернуть + закрыть.
  Widget _minimizedBar() {
    return GestureDetector(
      onPanUpdate: (d) => setState(() => _offset += d.delta),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accent.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _scientific ? 'Wesi Scientific' : 'Wesi Calculator',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      _result,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Уменьшить',
                icon: Icon(Icons.remove, size: 18, color: AppTheme.textMuted),
                onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.7, 1.4)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Увеличить',
                icon: Icon(Icons.add, size: 18, color: AppTheme.textMuted),
                onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.7, 1.4)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Развернуть',
                icon: Icon(Icons.open_in_full, size: 18, color: AppTheme.accent),
                onPressed: () => setState(() => _minimized = false),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Закрыть',
                icon: Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                onPressed: _close,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppTheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 6),
          Text(
            _scientific ? 'Wesi Scientific' : 'Wesi Calculator',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          // Mode toggle
          IconButton(
            tooltip: _scientific ? 'Классический' : 'Научный',
            icon: Icon(
              _scientific ? Icons.calculate_outlined : Icons.science_outlined,
              size: 18,
              color: _scientific ? AppTheme.accent : AppTheme.textMuted,
            ),
            onPressed: () => setState(() {
              _scientific = !_scientific;
              _second = false;
            }),
          ),
          IconButton(
            tooltip: _showHistory ? 'Скрыть историю' : 'История вычислений',
            icon: Icon(
              Icons.history,
              size: 18,
              color: _showHistory ? AppTheme.accent : AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _showHistory = !_showHistory),
          ),
          IconButton(
            tooltip: _showBlur ? 'Убрать блюр' : 'Включить блюр',
            icon: Icon(
              _showBlur ? Icons.blur_on : Icons.blur_off,
              size: 18,
              color: AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _showBlur = !_showBlur),
          ),
          IconButton(
            tooltip: _pinned ? 'Открепить' : 'Закрепить',
            icon: Icon(
              _pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 18,
              color: _pinned ? AppTheme.accent : AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _pinned = !_pinned),
          ),
          // Свернуть в полоску
          IconButton(
            tooltip: 'Свернуть',
            icon: Icon(Icons.minimize, size: 18, color: AppTheme.textMuted),
            onPressed: () => setState(() => _minimized = true),
          ),
          IconButton(
            tooltip: 'Уменьшить',
            icon: Icon(Icons.remove, size: 18, color: AppTheme.textMuted),
            onPressed: () =>
                setState(() => _scale = (_scale - 0.1).clamp(0.7, 1.4)),
          ),
          IconButton(
            tooltip: 'Увеличить',
            icon: Icon(Icons.add, size: 18, color: AppTheme.textMuted),
            onPressed: () =>
                setState(() => _scale = (_scale + 0.1).clamp(0.7, 1.4)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildDisplay() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_memory != 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'M',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          Text(
            _expression.isEmpty ? ' ' : _expression,
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 4),
          Text(
            _result,
            style: TextStyle(
              fontSize: _scientific ? 36 : 40,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _classicKeypad() {
    return Column(
      children: [
        _row(['C', 'DEL', '(', ')', '⌫']),
        const SizedBox(height: 8),
        _row(['7', '8', '9', '÷'], accentOps: true),
        const SizedBox(height: 8),
        _row(['4', '5', '6', '*'], accentOps: true),
        const SizedBox(height: 8),
        _row(['1', '2', '3', '-'], accentOps: true),
        const SizedBox(height: 8),
        _row(['0', '.', '=', '+'], accentOps: true),
      ],
    );
  }

  /// Раскладка максимально близка к присланному скрину.
  Widget _scientificKeypad() {
    final sinLabel = _second ? 'asin' : 'sin';
    final cosLabel = _second ? 'acos' : 'cos';
    final tanLabel = _second ? 'atan' : 'tg';
    final radLabel = _radians ? 'Rad' : 'Deg';

    return Column(
      children: [
        _row(['(', ')', 'mc', 'm+', 'm-', 'mr'], compact: true),
        const SizedBox(height: 5),
        _row(['2nd', 'x²', 'x³', 'xʸ', 'eˣ', '10ˣ'], compact: true),
        const SizedBox(height: 5),
        _row(['1/x', '√', '∛', 'ʸ√x', 'ln', 'log'], compact: true),
        const SizedBox(height: 5),
        _row(['x!', sinLabel, cosLabel, tanLabel, 'e', 'EE'], compact: true),
        const SizedBox(height: 5),
        _row(['Rand', 'sh', 'ch', 'th', 'π', radLabel], compact: true),
        const SizedBox(height: 8),
        _row(['⌫', 'AC', '%', '÷'], accentOps: true),
        const SizedBox(height: 6),
        _row(['7', '8', '9', '×'], accentOps: true),
        const SizedBox(height: 6),
        _row(['4', '5', '6', '−'], accentOps: true),
        const SizedBox(height: 6),
        _row(['1', '2', '3', '+'], accentOps: true),
        const SizedBox(height: 6),
        _row(['±', '0', '.', '='], accentOps: true),
      ],
    );
  }

  Widget _historyPanel() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: _history.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'История пуста',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(
                    children: [
                      Text(
                        'История',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(_history.clear),
                        child: Text(
                          'Очистить',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.accent),
                        ),
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
                              horizontal: 12, vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.expression,
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '= ${e.result}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
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

  Widget _row(
    List<String> keys, {
    bool compact = false,
    bool accentOps = false,
  }) {
    return Row(
      children: keys
          .map((t) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
                  child: _btn(t, compact: compact, accentOps: accentOps),
                ),
              ))
          .toList(),
    );
  }

  Widget _btn(String text, {bool compact = false, bool accentOps = false}) {
    Color? color;
    final isOp = ['÷', '×', '−', '+', '=', '%', '/', '*', '-'].contains(text);
    final isAc = text == 'AC' || text == 'C' || text == 'DEL' || text == '⌫';
    final isSecond = text == '2nd' && _second;
    final isRad = (text == 'Rad' || text == 'Deg');

    if (isAc) {
      color = AppTheme.accentRed;
    } else if (text == '=') {
      color = AppTheme.accentGreen;
    } else if (accentOps && isOp) {
      color = AppTheme.accent; // follows theme: orange dark / blue light
    } else if (isSecond || (isRad && !_radians)) {
      color = AppTheme.accent;
    }

    // Normalize display labels for operators
    String label = text;
    if (text == '÷') label = '÷';
    if (text == '×') label = '×';
    if (text == '−') label = '−';

    // Map visual ops to internal tokens
    final token = switch (text) {
      '÷' => '/',
      '×' => '*',
      '−' => '-',
      '±' => '+/-',
      _ => text,
    };

    final h = compact ? 38.0 : 50.0;
    final fs = compact ? 13.0 : 17.0;

    return GestureDetector(
      onTap: () => _onPressed(token),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: color != null ? color.withOpacity(0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          border: Border.all(
            color:
                color != null ? color.withOpacity(0.35) : AppTheme.glassBorder,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fs,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
