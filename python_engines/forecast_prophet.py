"""Прогноз чистого денежного потока через Prophet (Meta).

Вызывается как подпроцесс из Dart (ExternalForecastBridge). Контракт ввода
и вывода — см. _io_common.py.

interval_width=0.8 — по документации Prophet это и есть 80% доверительный
интервал (10-й / 90-й перцентиль при её внутреннем допущении о нормальности
ошибки), то есть ровно то, что нужно для P10/P90 без дополнительных плясок.
"""
import os
import sys

# Embeddable-дистрибутив Python (именно он лежит в бандле) задаёт sys.path
# ЦЕЛИКОМ файлом `python311._pth` и, в отличие от обычной установки, НЕ
# добавляет каталог запускаемого скрипта. Без этой строки соседний
# `_io_common.py` не находится и запуск падает с ModuleNotFoundError —
# одинаково и в CI, и у пользователя.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# CmdStan (нужен Prophet под капотом) собирается ОДИН РАЗ в CI —
# .github/workflows/build-engines.yml — и кладётся в `python/cmdstan/` того
# же zip-бандла, что скачивает EngineInstallService. На машине пользователя
# нет C++ тулчейна, чтобы собрать CmdStan самому, поэтому важно указать
# cmdstanpy путь до готового бинарника, а не дать ему пытаться найти/собрать
# CmdStan заново (уйдёт в ValueError "No CmdStan installation found").
#
# Путь ищем ОТНОСИТЕЛЬНО sys.executable, а не по абсолютному пути, записанному
# во время сборки: у пользователя бандл лежит в другом месте (обычно
# ApplicationSupportDirectory), чем на CI-раннере, где он собирался — жёстко
# зашитый build-time путь на машине пользователя просто не существовал бы.
_cmdstan_root = os.path.join(os.path.dirname(sys.executable), "cmdstan")
if os.path.isdir(_cmdstan_root):
    _versions = sorted(
        d for d in os.listdir(_cmdstan_root)
        if os.path.isdir(os.path.join(_cmdstan_root, d))
    )
    if _versions:
        # Обычно ровно одна версия — берём последнюю по имени на случай,
        # если когда-нибудь окажется больше одной.
        os.environ["CMDSTAN"] = os.path.join(_cmdstan_root, _versions[-1])
# Если каталога нет вовсе (локальная разработка, системный Python с уже
# настроенным cmdstanpy) — просто не трогаем, пусть cmdstanpy сам решает.

import warnings
import pandas as pd
from prophet import Prophet

from _io_common import read_input, emit_error, emit_success, to_balance_trajectory, MIN_HISTORY_DAYS

warnings.filterwarnings("ignore")


def main():
    history, days, current_balance = read_input()

    if len(history) < MIN_HISTORY_DAYS:
        emit_error("insufficient_data", f"need >= {MIN_HISTORY_DAYS} days, got {len(history)}")
        return

    df = pd.DataFrame({
        "ds": pd.to_datetime([h["date"] for h in history]),
        "y": [h["net"] for h in history],
    })

    try:
        model = Prophet(
            interval_width=0.8,
            daily_seasonality=False,
            weekly_seasonality=True,
            yearly_seasonality="auto",
        )
        model.fit(df)
        future = model.make_future_dataframe(periods=days, include_history=False)
        forecast = model.predict(future)
    except Exception as e:  # noqa: BLE001
        emit_error("fit_failed", str(e))
        return

    p50 = to_balance_trajectory(forecast["yhat"].tolist(), current_balance)
    p10 = to_balance_trajectory(forecast["yhat_lower"].tolist(), current_balance)
    p90 = to_balance_trajectory(forecast["yhat_upper"].tolist(), current_balance)
    p10, p90 = [min(a, b) for a, b in zip(p10, p90)], [max(a, b) for a, b in zip(p10, p90)]

    emit_success("prophet", p10, p50, p90, len(history))


if __name__ == "__main__":
    main()
