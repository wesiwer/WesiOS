# Wesi AI Audio — Quick Analysis v2

## Что добавлено

- анализ выполняется локально и вынесен в отдельный isolate;
- поддерживается mono/stereo WAV PCM 16/24/32-bit, IEEE Float 32-bit и WAVE_FORMAT_EXTENSIBLE с PCM/Float sub-format;
- Sample Peak и быстрый True Peak estimate;
- Integrated LUFS estimate;
- RMS и Crest Factor;
- PLR (Peak-to-Loudness Ratio);
- приблизительный LRA;
- приблизительные Max Momentary (~400 ms) и Max Short-term (~3 s);
- stereo correlation;
- средний L/R balance;
- Mid/Side energy ratio;
- DC offset;
- число clipped samples и плотность clipping на миллион samples;
- тишина в начале/конце и её доля;
- спектральный баланс Sub/Bass/Low-mid/Mid/Presence/High/Air;
- локальные Wesi AI Audio рекомендации по clipping, over-limiting, phase/mono, stereo width, channel balance, DC, low-end, mud, harshness и export settings.

## Delivery checks

### Spotify

Используются опубликованные Spotify mastering tips: Normal playback ориентируется на -14 LUFS, True Peak максимум -1 dBTP; для masters громче -14 LUFS Spotify рекомендует держать True Peak ниже -2 dBTP. В интерфейсе это маркируется как `Official guidance`.

### Apple Digital Masters

Проверяется та часть official source profile, которую можно определить по самому WAV: 24-bit и допустимый sample rate 44.1/48/88.2/96/176.4/192 kHz, а также отсутствие digital clipping. WesiOS не заявляет, что может проверить происхождение исходника, отсутствие upsampling/bit-padding или заменить обязательное audition Apple AAC encoder.

### EBU R128

Показывается как `Broadcast reference`, а не как streaming target. Quick Analysis сравнивает оценку с -23 LUFS и true-peak reference, но не выдаёт это за сертифицированный R128 compliance test.

### YouTube

WesiOS не показывает выдуманный фиксированный «YouTube LUFS standard». Официальная справка YouTube описывает automatic audio enhancements/Stable volume, но используемая документация не задаёт fixed upload mastering LUFS target. Поэтому показывается только внутренний `Wesi QC` по clipping/headroom.

## Защита от устаревших результатов

Отчёт запоминает путь, размер и modified time WAV. Если файл заменён или изменён, старые цифры автоматически скрываются и WesiOS требует повторный анализ.

## Ableton

Кроме выбора `.als` через file picker можно вручную вставить полный путь. Перед сохранением WesiOS удаляет внешние кавычки, проверяет расширение `.als` и существование файла. Исходный проект не копируется и не удаляется WesiOS.

## Ограничения

LUFS/LRA/Momentary/Short-term и True Peak в Quick Analysis v2 остаются быстрыми оценками. Для обязательного delivery compliance нужен standards-compliant BS.1770/EBU R128 meter, а для Apple Digital Masters — предусмотренный Apple AAC encode audition.
