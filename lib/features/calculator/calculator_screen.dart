import 'package:flutter/material.dart';
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

  void _onPressed(String value) {
    setState(() {
      if (value == 'C') {
        _expression = '';
        _result = '0';
      } else if (value == '=') {
        try {
          Parser p = Parser();
          Expression exp = p.parse(_expression);
          ContextModel cm = ContextModel();
          _result = exp.evaluate(EvaluationType.REAL, cm).toString();
        } catch (e) {
          _result = 'Error';
        }
      } else if (value == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else {
        _expression += value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Калькулятор')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_expression, style: const TextStyle(fontSize: 24, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text(_result, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _buildButton('C', AppTheme.accentRed),
                _buildButton('(', AppTheme.textSecondary),
                _buildButton(')', AppTheme.textSecondary),
                _buildButton('⌫', AppTheme.accentOrange),
                _buildButton('7'),
                _buildButton('8'),
                _buildButton('9'),
                _buildButton('/', AppTheme.accentOrange),
                _buildButton('4'),
                _buildButton('5'),
                _buildButton('6'),
                _buildButton('*', AppTheme.accentOrange),
                _buildButton('1'),
                _buildButton('2'),
                _buildButton('3'),
                _buildButton('-', AppTheme.accentOrange),
                _buildButton('0'),
                _buildButton('.'),
                _buildButton('=', AppTheme.accentGreen),
                _buildButton('+', AppTheme.accentOrange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String text, [Color? color]) {
    return GestureDetector(
      onTap: () => _onPressed(text),
      child: Container(
        decoration: BoxDecoration(
          color: color != null ? color.withOpacity(0.2) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
