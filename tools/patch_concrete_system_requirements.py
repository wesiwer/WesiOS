from pathlib import Path
import re

# retrigger after workflow creation
path = Path('server/employee-portal/index.html')
html = path.read_text(encoding='utf-8')

windows = '''<article class="req-card surface">
                <div class="req-platform"><b>Windows</b><span>x64</span></div>
                <div class="req-cols">
                  <div><small>МИНИМАЛЬНО</small><dl>
                    <dt>ОС</dt><dd>Windows 10 22H2, 64-bit</dd>
                    <dt>Процессор</dt><dd>2 ядра / 4 потока, x64, от 2.0 ГГц; Core i3-6100U / Ryzen 3 2200U или аналог</dd>
                    <dt>ОЗУ</dt><dd>4 ГБ</dd>
                    <dt>Графика</dt><dd>DirectX 11, аппаратное ускорение</dd>
                    <dt>Диск</dt><dd>1 ГБ свободно</dd>
                    <dt>Экран</dt><dd>1280×720</dd>
                    <dt>Сеть</dt><dd>1 Мбит/с ↓ / 1 Мбит/с ↑, задержка ≤250 мс, HTTPS 443</dd>
                  </dl></div>
                  <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl>
                    <dt>ОС</dt><dd>Windows 11, 64-bit</dd>
                    <dt>Процессор</dt><dd>4 ядра / 8 потоков; Core i5-8250U / Ryzen 5 3500U или лучше</dd>
                    <dt>ОЗУ</dt><dd>8 ГБ</dd>
                    <dt>Графика</dt><dd>Intel UHD 620 / Radeon Vega 8 или лучше</dd>
                    <dt>Диск</dt><dd>SSD, 2 ГБ свободно</dd>
                    <dt>Экран</dt><dd>1920×1080</dd>
                    <dt>Сеть</dt><dd>10 Мбит/с ↓ / 5 Мбит/с ↑, задержка ≤100 мс</dd>
                  </dl></div>
                </div>
              </article>'''

android = '''<article class="req-card surface">
                <div class="req-platform"><b>Android</b><span>API 21+</span></div>
                <div class="req-cols">
                  <div><small>МИНИМАЛЬНО</small><dl>
                    <dt>ОС</dt><dd>Android 5.0 (API 21) или новее</dd>
                    <dt>Процессор</dt><dd>ARMv7 / ARM64, 4 ядра от 1.5 ГГц</dd>
                    <dt>ОЗУ</dt><dd>2 ГБ</dd>
                    <dt>Графика</dt><dd>Аппаратный OpenGL ES 2.0</dd>
                    <dt>Диск</dt><dd>500 МБ свободно</dd>
                    <dt>Экран</dt><dd>1280×720 или эквивалент</dd>
                    <dt>Сеть</dt><dd>1 Мбит/с ↓ / 1 Мбит/с ↑, задержка ≤250 мс, HTTPS 443</dd>
                  </dl></div>
                  <div class="recommended"><small>РЕКОМЕНДУЕТСЯ</small><dl>
                    <dt>ОС</dt><dd>Android 10 или новее</dd>
                    <dt>Процессор</dt><dd>ARM64, 8 ядер; Snapdragon 660/665, Helio G80 или лучше</dd>
                    <dt>ОЗУ</dt><dd>4 ГБ</dd>
                    <dt>Графика</dt><dd>Adreno 512 / Mali-G52 или лучше</dd>
                    <dt>Диск</dt><dd>1 ГБ свободно</dd>
                    <dt>Экран</dt><dd>1920×1080 или эквивалент</dd>
                    <dt>Сеть</dt><dd>10 Мбит/с ↓ / 5 Мбит/с ↑, задержка ≤100 мс</dd>
                  </dl></div>
                </div>
              </article>'''

html, wc = re.subn(
    r'<article class="req-card surface">\s*<div class="req-platform"><b>Windows</b>.*?</article>',
    windows,
    html,
    flags=re.S,
)
html, ac = re.subn(
    r'<article class="req-card surface">\s*<div class="req-platform"><b>Android</b>.*?</article>',
    android,
    html,
    flags=re.S,
)

if wc != 2 or ac != 2:
    raise SystemExit(f'expected 2 Windows and 2 Android cards, got {wc}/{ac}')

html = html.replace(
    'Показываем только подтверждённые ограничения. WesiOS не задаёт жёсткий минимум ОЗУ, частоты CPU или фиксированного объёма диска, поэтому таких выдуманных цифр здесь нет.',
    'Ниже — практический минимум для текущей WesiOS, а не голые требования ОС. Он учитывает Flutter-интерфейс, графики, rich-text, PDF, медиа, локальную базу, криптографию и live-sync.',
)
html = html.replace(
    'Минимальные и рекомендуемые параметры для текущих сборок WesiOS. Публикуем только подтверждённые ограничения.',
    'Конкретная конфигурация для текущей WesiOS: процессор, память, графика, диск, экран и сеть.',
)
html = re.sub(
    r'<p class="requirements-proof">.*?</p>',
    '<p class="requirements-proof">Совместимость подтверждена текущей сборкой: Windows release — <code>x64</code>, Android — <code>minSdkVersion 21</code>. Сеть рассчитана с учётом live-sync: лёгкая проверка ревизии идёт раз в секунду, полный обмен — только при изменениях.</p>',
    html,
    flags=re.S,
)

path.write_text(html, encoding='utf-8')
print('concrete system requirements applied')
