from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'anchor not found: {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    "rng.nextInt(max(1, spanDays - min(blockLength, spanDays) + 1))",
    "rng.nextInt(max(1, spanDays - min(blockLength, spanDays) + 1).toInt())",
)

replace_once(
    'lib/features/treasury/services/horizon_engine_competition.dart',
    "import 'forecast_engine_kind.dart';\nimport 'multi_engine_forecast.dart';",
    "import 'forecast_engine_kind.dart';\nimport 'horizon_calibration.dart';\nimport 'multi_engine_forecast.dart';",
)

replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """        final renewalAmount = contract.renewalAmountRub > 0
            ? contract.renewalAmountRub
            : lease.amount;
""",
    """        final renewalAmount = contract.renewalAmountRub > 0
            ? contract.renewalAmountRub
            : lease.amount *
                CurrencyService.rateToRub(lease.currency.toLowerCase());
""",
)

print('Horizon compile/currency fixes applied')
