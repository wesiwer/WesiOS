import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';
import '../../core/theme/app_theme.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = '';
  String _result = '0';
  final FocusNode _focusNode = FocusNode();

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
      } else if (value == 'Delete' || value == 'DEL') {
        _expression = '';
        _result = '0';
      } else if (value == '=' || value == 'Enter') {
        _calculate();
      } else if (value == '⌫' || value == 'Backspace') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (_isValidInput(value)) {
        _expression += value;
      }
    });
  }

  bool _isValidInput(String value) {
    const valid = '0123456789.+-*/()^%';
    return valid.contains(value);
  }

  void _calculate() {
    if (_expression.isEmpty) return;
    try {
      final p = Parser();
      final exp = p.parse(_expression);
      final cm = ContextModel();
      final eval = exp.evaluate(EvaluationType.REAL, cm);
      _result =
          eval == eval.toInt() ? eval.toInt().toString() : eval.toString();
    } catch (_) {
      _result = 'Error';
    }
  }

  String? _mapNumpad(LogicalKeyboardKey key) {
    const map = {
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
    return map[key];
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (!_pinned) Navigator.pop(context);
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
          child: Container(
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
                          onPressed: () => Navigator.pop(context),
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
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            // Backdrop: плавный fade без тяжёлого blur при каждом кадре
            if (_showBlur)
              GestureDetector(
                onTap: _pinned ? null : () => Navigator.pop(context),
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: _pinned ? null : () => Navigator.pop(context),
                child: Container(color: Colors.transparent),
              ),
            Center(child: panel),
          ],
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
    if (text == 'C' || text == 'DEL') color = AppTheme.accentRed;
    else if (text == '=') color = AppTheme.accentGreen;
    else if (['/', '*', '-', '+', '⌫'].contains(text)) {
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
