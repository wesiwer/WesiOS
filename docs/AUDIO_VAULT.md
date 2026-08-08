# Audio Vault — WesiOS

Статус: **ready**.

Audio Vault — рабочий архив музыкальных проектов Wesi Inc. Это не просто список файлов: карточка бита связывает мастер-файлы, исходный Ableton Live project, автора, сделку/аренду, документы, комментарии, календарное напоминание и локальный технический анализ.

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
- аренда/сделка.

Поиск охватывает название, автора, арендатора, ссылку на соцсеть, жанр, настроение, тональность, теги и заметки.

Фильтры: стадия, автор, диапазон BPM, избранное.

Сортировки: последнее изменение, создание, название, BPM, автор, стадия, ближайшее окончание аренды.

MP3/WAV/Track Out можно отправить/достать из карточки одним нажатием.

## Ableton Live

У бита можно сохранить путь к исходному `.als`.

WesiOS не копирует Ableton project в собственное хранилище: ссылка остаётся на оригинальный проект, чтобы Ableton продолжал работать с привычным расположением samples/packs.

На desktop кнопка `Открыть в Ableton` открывает `.als` через системную ассоциацию файлов:

- Windows — `start`;
- macOS — `open`;
- Linux — `xdg-open`.

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

## Wesi AI Audio — Quick Analysis

Это первая полностью локальная специализированная ветвь Wesi AI. Аудиофайл не отправляется на сервер.

Для анализа используется прикреплённый WAV master. Сейчас поддерживается mono/stereo WAV PCM/IEEE Float 16/24/32 bit.

Проверяется:

- Sample Peak;
- быстрый True Peak estimate с интерполяцией;
- RMS;
- быстрый Integrated LUFS estimate;
- Crest Factor;
- digital clipping;
- DC offset;
- stereo correlation / риск mono phase cancellation;
- тишина в начале и конце файла;
- sample rate / bit depth / channels / duration;
- спектральный баланс по Sub, Bass, Low-mid, Mid, Presence, High, Air;
- возможный excess sub;
- low-mid mud;
- harsh presence/highs;
- over-limiting / потеря punch;
- streaming true-peak headroom.

Результат хранится вместе с extended metadata бита: score 0–100, метрики, проверки и список конкретных действий.

### Platform checks

Жёсткий target показывается только там, где есть публикуемый ориентир. Нельзя выдавать интернет-мифы о «стандартах каждой площадки» за официальный mastering spec.

- Spotify Normal: сравнение с опубликованным ориентиром normalization и true-peak recommendation.
- Wesi Streaming Safe: внутренний универсальный QC по clipping/headroom; это не заявляется как официальный норматив конкретной площадки.
- EBU R128: показывается как broadcast reference, а не как обязательная цель музыкального streaming master.

### Ограничение Quick Analysis

Текущие LUFS/True Peak помечены `est.`. Это быстрый локальный QC, а не сертифицированная реализация BS.1770/R128 meter. Для юридически/технически обязательного delivery QC нужен точный standards-compliant meter с K-weighting, gating и true-peak oversampling по стандарту.

Это ограничение показывается пользователю прямо в UI; WesiOS не выдаёт приближение за сертифицированное измерение.

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
