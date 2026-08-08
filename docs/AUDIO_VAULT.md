# Audio Vault — WesiOS

Статус: **ready**.

Audio Vault — рабочий архив музыкальных проектов Wesi Inc. Карточка бита связывает мастер-файлы, исходный Ableton Live project, автора, сделку/аренду, документы, комментарии, календарное напоминание, локальный плеер и специализированную локальную ветвь Wesi AI Audio.

## Архив битов

Для каждого бита сохраняются:

- название;
- автор из сотрудников WesiOS;
- стадия: idea / draft / production / mixing / mastering / ready / negotiating / leased / sold / exclusive / archived;
- BPM, тональность, жанр, настроение;
- произвольные теги и заметки;
- обложка;
- MP3;
- WAV master;
- Track Out архив;
- документы и договоры;
- история комментариев;
- избранное;
- аренда/сделка;
- путь к исходному Ableton Live `.als`;
- последний актуальный отчёт Wesi AI Audio.

Поиск охватывает название, автора, арендатора, ссылку на соцсеть, жанр, настроение, тональность, теги и заметки.

Фильтры: стадия, автор, диапазон BPM, избранное.

Сортировки: последнее изменение, создание, название, BPM, автор, стадия, ближайшее окончание аренды.

MP3/WAV/Track Out можно отправить/достать из карточки одним нажатием.

## Ableton Live

У каждого бита можно сохранить путь к исходному `.als` двумя способами:

- выбрать файл через системный file picker;
- вставить полный путь вручную.

При ручном вводе WesiOS убирает внешние кавычки, проверяет расширение `.als`, существование файла и сохраняет абсолютный путь.

WesiOS не копирует Ableton project в собственное хранилище: ссылка остаётся на оригинальный проект, чтобы Ableton продолжал работать с привычным расположением samples/packs.

На desktop кнопка `Открыть в Ableton` открывает `.als` через системную ассоциацию файлов:

- Windows — `start`;
- macOS — `open`;
- Linux — `xdg-open`.

Если проект был перемещён, карточка показывает, что файл больше не найден, и позволяет сразу указать новый путь.

Удаление записи Audio Vault **не удаляет исходный `.als`**.

## Аренда и календарь

У сделки/аренды есть:

- исполнитель/покупатель;
- ссылка на социальную сеть;
- дата начала;
- дата окончания/продления;
- сумма и валюта;
- комментарий.

В карточке и архиве показывается живой countdown до окончания аренды.

Audio Vault создаёт связанную задачу `audio-vault/lease` с `dueDate`. Существующий Calendar читает сроки из TaskService, поэтому окончание аренды автоматически появляется в календаре без второго источника дат.

При продлении задача перезаписывается новым сроком. При закрытии аренды или удалении бита связанное напоминание удаляется.

## Player

Локальный player основан на `flutter_soloud` и работает поверх всей WesiOS.

Поддерживаются:

- очередь;
- play/pause;
- seek;
- previous/next;
- volume;
- плавающий mini-player при переходе в другие модули;
- реальный FFT и waveform data.

### Визуализаторы

Минимум восемь режимов:

1. Water Tank;
2. Membrane;
3. Spectrum;
4. Particles;
5. Tunnel;
6. Aurora;
7. Orbit;
8. Pulse Grid.

Water Tank реагирует на реальный сигнал: bass управляет крупной волной, high — мелкой рябью, kick transient — ударом и брызгами.

## Music Hub

Отдельная библиотека обычной музыки не смешивается с архивом битов.

Локально импортируются MP3/WAV/OGG/FLAC. Файлы копируются в приватную папку Music Hub и сохраняются в очереди после перезапуска WesiOS.

## Spotify Connect

Интеграция использует Spotify Web API и Authorization Code with PKCE:

- Client Secret внутри WesiOS не хранится;
- Client ID вводится владельцем;
- access/refresh tokens сохраняются в secure storage;
- OAuth callback принимается локальным loopback server `127.0.0.1`;
- playback state восстанавливается при запуске WesiOS;
- доступны current track/artwork/device, play/pause, previous/next, seek и volume;
- Spotify transport отображается и в глобальном mini-player.

Playback-control Web API требует подходящего Spotify аккаунта и активного Spotify Connect устройства; ошибки API не маскируются под локальное воспроизведение.

## Wesi AI Audio — Quick Analysis v2

Это специализированная полностью локальная ветвь Wesi AI. Аудиофайл не отправляется на сервер.

Тяжёлая часть анализа выполняется в отдельном isolate через `compute`, поэтому большой WAV не должен блокировать основной UI isolate.

Для анализа используется прикреплённый WAV master. Поддерживаются:

- mono/stereo;
- PCM 16/24/32-bit;
- IEEE Float 32-bit;
- `WAVE_FORMAT_EXTENSIBLE` с PCM/Float sub-format.

### Метрики

Quick Analysis v2 считает:

- Sample Peak;
- быстрый True Peak estimate с inter-sample interpolation;
- RMS;
- Integrated LUFS estimate;
- Crest Factor;
- PLR — Peak-to-Loudness Ratio;
- приблизительный LRA;
- Max Momentary loudness estimate (~400 ms);
- Max Short-term loudness estimate (~3 s);
- digital clipping;
- число clipped samples на миллион samples;
- DC offset;
- stereo correlation / риск mono phase cancellation;
- средний L/R balance в dB;
- Mid/Side energy ratio;
- тишину в начале и конце;
- долю edge silence;
- sample rate / bit depth / channels / duration;
- спектральный баланс по Sub, Bass, Low-mid, Mid, Presence, High, Air.

### Wesi AI Audio — диагностика

На основании метрик локальная логика формирует score 0–100 и конкретные замечания/действия, в том числе:

- digital clipping;
- нехватка true-peak headroom;
- чрезмерная integrated loudness;
- low PLR / возможный over-limiting;
- слишком узкий loudness range;
- потеря punch/transients;
- дисбаланс L/R;
- высокая Side-энергия;
- отрицательная/низкая stereo correlation;
- риск mono phase cancellation;
- DC offset;
- неподходящий sample rate / bit depth для выбранного delivery;
- слишком длинная тишина в начале/конце;
- excess sub;
- low-mid mud;
- harsh presence/highs;
- слишком громкие краткие участки.

Спектральные выводы являются эвристиками и всегда формулируются как повод проверить диапазон на слух/референсе, а не как автоматическая команда эквализации.

### Проверки площадок / delivery

Каждая карточка показывает основание проверки, чтобы внутренний Wesi QC нельзя было перепутать с официальным требованием площадки.

- **Spotify · Normal** — `Official guidance`: сравнение с опубликованным ориентиром loudness normalization и true-peak mastering tips.
- **Apple Digital Masters · source profile** — `Official source profile`: проверяется та часть source profile, которую можно установить по самому WAV — bit depth, допустимый sample rate и отсутствие digital clipping. WesiOS не выдаёт эту проверку за доказательство происхождения исходника или замену Apple AAC encode audition.
- **EBU R128 · broadcast reference** — `Broadcast reference`: сравнение с broadcast loudness reference, а не с обязательным streaming target.
- **YouTube · technical playback QC** — `Wesi QC · not an official LUFS target`: WesiOS не выдумывает фиксированный upload LUFS target, если его нет в используемой официальной документации; проверяется clipping/headroom перед транскодированием.
- **Wesi Streaming Safe** — внутренний универсальный QC по clipping/headroom и mono/stereo delivery.

### Защита от устаревшего анализа

Каждый отчёт сохраняет:

- путь к WAV;
- размер файла;
- modified time.

Если WAV был заменён или изменён после анализа, старый отчёт автоматически скрывается. Пользователь видит предупреждение и должен запустить анализ заново. Старые отчёты v1 без fingerprint также считаются устаревшими, чтобы WesiOS не показывал старые цифры как актуальные.

### Ограничения Quick Analysis

LUFS/LRA/Momentary/Short-term и True Peak помечены `est.`. Quick Analysis — быстрый локальный технический QC, а не сертифицированная реализация BS.1770/R128 meter.

Для обязательного delivery compliance нужен standards-compliant meter с требуемым weighting/gating/true-peak oversampling. Для Apple Digital Masters отдельно требуется предусмотренная Apple проверка AAC encode.

Это ограничение показывается пользователю прямо в UI; WesiOS не выдаёт приближение за сертифицированное измерение.

## Тесты Quick Analysis v2

Добавлены два уровня автоматической проверки:

- JSON round-trip/backward compatibility новой модели анализа;
- runtime-тест, который создаёт настоящий синтетический PCM WAV, запускает его через локальный analyzer/isolate и проверяет метрики и delivery checks.

## Хранение

Основная BeatEntry-база: Hive `wesios_audio_vault / beats_v1`.

Extended metadata (Ableton + Audio AI report): `extended_meta_v1`.

Music Hub index: `music_library_v1`.

Копии файлов Audio Vault находятся внутри application documents. Исходный `.als` хранится только по ссылке.

При удалении бита очищаются:

- BeatEntry;
- копии MP3/WAV/Track Out/cover/documents внутри Audio Vault;
- extended metadata;
- связанная lease reminder task.

Исходный Ableton project не удаляется.
