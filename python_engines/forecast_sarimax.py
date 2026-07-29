"""Прогноз чистого денежного потока через statsmodels SARIMAX.

Вызывается как подпроцесс из Dart (ExternalForecastBridge). Контракт ввода
и вывода — см. _io_common.py.

Порядок модели (1,1,1)x(1,1,1,7): недельная сезонность (период 7 дней),
единичное дифференцирование по тренду и по сезону — разумный общий дефолт,
не подобранный под конкретные данные (в отличие от auto_arima, который сюда
намеренно не подключён — тянет pmdarima, ещё одну тяжёлую и менее стабильную
на Windows зависимость). Если сезонная модель не сходится (мало истории),
откатываемся на простой ARIMA(1,1,1) без сезонной части.
"""
import os
import sys
import warnings

# Embeddable-дистрибутив Python (именно он лежит в бандле) задаёт sys.path
# ЦЕЛИКОМ файлом `python311._pth` и, в отличие от обычной установки, НЕ
# добавляет каталог запускаемого скрипта. Без этой строки соседний
# `_io_common.py` не находится и запуск падает с ModuleNotFoundError —
# одинаково и в CI, и у пользователя.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import pandas as pd
from statsmodels.tsa.statespace.sarimax import SARIMAX

from _io_common import read_input, emit_error, emit_success, to_balance_trajectory, MIN_HISTORY_DAYS

warnings.filterwarnings("ignore")


def fit_and_forecast(series: pd.Series, steps: int):
    orders_to_try = [
        ((1, 1, 1), (1, 1, 1, 7)),  # недельная сезонность
        ((1, 1, 1), (0, 0, 0, 0)),  # откат: без сезонной части
    ]
    last_error = None
    for order, seasonal_order in orders_to_try:
        try:
            model = SARIMAX(
                series,
                order=order,
                seasonal_order=seasonal_order,
                enforce_stationarity=False,
                enforce_invertibility=False,
            )
            fitted = model.fit(disp=False)
            forecast = fitted.get_forecast(steps=steps)
            summary = forecast.summary_frame(alpha=0.20)  # 80% CI -> P10/P90
            return summary["mean"].tolist(), summary["mean_ci_lower"].tolist(), summary["mean_ci_upper"].tolist()
        except Exception as e:  # noqa: BLE001 — любая ошибка модели -> пробуем проще/сдаёмся
            last_error = e
            continue
    raise RuntimeError(f"all SARIMAX orders failed: {last_error}")


def main():
    history, days, current_balance = read_input()

    if len(history) < MIN_HISTORY_DAYS:
        emit_error("insufficient_data", f"need >= {MIN_HISTORY_DAYS} days, got {len(history)}")
        return

    dates = pd.to_datetime([h["date"] for h in history])
    values = np.array([h["net"] for h in history], dtype=float)
    series = pd.Series(values, index=pd.DatetimeIndex(dates))
    series.index.freq = "D"

    try:
        mean, lower, upper = fit_and_forecast(series, days)
    except Exception as e:  # noqa: BLE001
        emit_error("fit_failed", str(e))
        return

    p50 = to_balance_trajectory(mean, current_balance)
    p10 = to_balance_trajectory(lower, current_balance)
    p90 = to_balance_trajectory(upper, current_balance)
    # SARIMAX не гарантирует lower <= upper по построению интервала на каждой
    # точке при откате на более простую модель — подстрахуемся сортировкой.
    p10, p90 = [min(a, b) for a, b in zip(p10, p90)], [max(a, b) for a, b in zip(p10, p90)]

    emit_success("sarimax", p10, p50, p90, len(history))


if __name__ == "__main__":
    main()
