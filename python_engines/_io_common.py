"""Общий контракт ввода/вывода для forecast_prophet.py и forecast_sarimax.py.

Оба скрипта читают из stdin один и тот же JSON:
    {"history": [{"date": "YYYY-MM-DD", "net": float}, ...],  # по дням, без пропусков
     "days": int,                                              # горизонт прогноза
     "current_balance": float}

И пишут в stdout один и тот же JSON:
    успех: {"engine": "...", "p10": [...], "p50": [...], "p90": [...], "history_days": int}
    ошибка: {"error": "insufficient_data" | "fit_failed", "detail": "..."}

Важное упрощение (в отличие от родного Dart-движка ForecastEngine, который
разделяет доходы и расходы на два независимых потока): здесь прогнозируется
ОДИН ряд — чистый дневной денежный поток (доход минус расход). Это стандартный
вход для Prophet/SARIMAX как готовых библиотек временных рядов, и совпадающий
контракт даёт честное сравнение "движок против движка" на одних и тех же
данных. Разделение по доходу/расходу для этих двух движков не поддерживается
(в частности, множители «Что если?» к ним неприменимы) — см. STATUS.md.
"""
import sys
import json


MIN_HISTORY_DAYS = 14


def read_input():
    raw = sys.stdin.read()
    payload = json.loads(raw)
    history = payload["history"]
    days = int(payload["days"])
    current_balance = float(payload["current_balance"])
    return history, days, current_balance


def emit_error(kind: str, detail: str = "") -> None:
    print(json.dumps({"error": kind, "detail": detail}))


def emit_success(engine: str, p10, p50, p90, history_days: int) -> None:
    print(json.dumps({
        "engine": engine,
        "p10": [round(float(v), 2) for v in p10],
        "p50": [round(float(v), 2) for v in p50],
        "p90": [round(float(v), 2) for v in p90],
        "history_days": history_days,
    }))


def to_balance_trajectory(daily_net_forecast, current_balance):
    """Кумулятивная сумма прогноза дневного нетто + текущий баланс.

    Это приближение: складывать нижнюю/верхнюю границы независимо по дням
    статистически не совсем строго (неопределённость должна расти как
    корень суммы дисперсий, а не складываться линейно), но для режима
    сравнения движков (не более того) — разумный и прозрачный компромисс,
    задокументированный в STATUS.md.
    """
    balance = current_balance
    out = []
    for v in daily_net_forecast:
        balance += v
        out.append(balance)
    return out
