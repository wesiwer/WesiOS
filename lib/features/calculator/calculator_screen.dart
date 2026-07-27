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
      if (value == 'C' || value == 'c' || value == 'Escape') {
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
      Parser p = Parser();
      Expression exp = p.parse(_expression);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);
      _result = eval == eval.toInt() ? eval.toInt().toString() : eval.toString();
    } catch (e) {
      _result = 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 580),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.glassBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                title: const Text(
                  'Wesi Калькулятор',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: KeyboardListener(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
                      _onPressed('Enter');
                    } else if (key == LogicalKeyboardKey.backspace) {
                      _onPressed('Backspace');
                    } else if (key == LogicalKeyboardKey.escape) {
                      _onPressed('Escape');
                    } else {
                      final char = key.keyLabel;
                      if (char.length == 1) _onPressed(char);
                    }
                  }
                },
                child: Column(
                  children: [
                    // Display
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.bottomRight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _expression,
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _result,
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Buttons — no scroll, fixed layout
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          _buildButtonRow(['C', '(', ')', '⌫']),
                          const SizedBox(height: 10),
                          _buildButtonRow(['7', '8', '9', '/']),
                          const SizedBox(height: 10),
                          _buildButtonRow(['4', '5', '6', '*']),
                          const SizedBox(height: 10),
                          _buildButtonRow(['1', '2', '3', '-']),
                          const SizedBox(height: 10),
                          _buildButtonRow(['0', '.', '=', '+']),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonRow(List<String> buttons) {
    return Row(
      children: buttons.map((text) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _buildButton(text),
        ),
      )).toList(),
    );
  }

  Widget _buildButton(String text) {
    Color? color;
    if (text == 'C') color = AppTheme.accentRed;
    else if (text == '=') color = AppTheme.accentGreen;
    else if (['/', '*', '-', '+', '⌫'].contains(text)) color = AppTheme.accentOrange;
    else if (['(', ')'].contains(text)) color = AppTheme.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onPressed(text),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 56,
          decoration: BoxDecoration(
            color: color != null ? color.withOpacity(0.15) : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color != null ? color.withOpacity(0.3) : AppTheme.glassBorder,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: color ?? AppTheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
