#!/usr/bin/env python3
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
import os, shutil

root = Path(os.environ['RUNNER_TEMP']) / 'google-fonts'
out = Path(os.environ['WESIMARK_ROOT']) / 'assets/fonts'
out.mkdir(parents=True, exist_ok=True)

targets = {
 'PTSans.ttf':('ptsans',400),'PTSans-Bold.ttf':('ptsans',700),
 'Roboto.ttf':('roboto',400),'Roboto-Bold.ttf':('roboto',700),
 'Inter.ttf':('inter',400),'Inter-Bold.ttf':('inter',700),
 'Montserrat.ttf':('montserrat',400),'Montserrat-Bold.ttf':('montserrat',700),
 'Rubik.ttf':('rubik',400),'Rubik-Bold.ttf':('rubik',700),
 'Ubuntu.ttf':('ubuntu',400),'Ubuntu-Bold.ttf':('ubuntu',700),
 'PTSansNarrow.ttf':('ptsansnarrow',400),'PTSansNarrow-Bold.ttf':('ptsansnarrow',700),
 'RobotoCondensed.ttf':('robotocondensed',400),'RobotoCondensed-Bold.ttf':('robotocondensed',700),
 'FiraSansCondensed.ttf':('firasanscondensed',400),'FiraSansCondensed-Bold.ttf':('firasanscondensed',700),
 'Oswald.ttf':('oswald',400),'Oswald-Bold.ttf':('oswald',700),
 'PTSerif.ttf':('ptserif',400),'PTSerif-Bold.ttf':('ptserif',700),
 'Lora.ttf':('lora',400),'Lora-Bold.ttf':('lora',700),
 'PlayfairDisplay.ttf':('playfairdisplay',400),'PlayfairDisplay-Bold.ttf':('playfairdisplay',700),
 'RobotoMono.ttf':('robotomono',400),'RobotoMono-Bold.ttf':('robotomono',700),
 'RussoOne.ttf':('russoone',400),'YesevaOne.ttf':('yesevaone',400),
 'Comfortaa.ttf':('comfortaa',400),'Comfortaa-Bold.ttf':('comfortaa',700),
 'Caveat.ttf':('caveat',400),'Caveat-Bold.ttf':('caveat',700),
 'BadScript.ttf':('badscript',400),'MarckScript.ttf':('marckscript',400),
}

for name, (slug, weight) in targets.items():
    dirs = [p for p in root.rglob(slug) if p.is_dir()]
    files = []
    for d in dirs:
        files.extend(p for p in d.glob('*.ttf') if 'italic' not in p.name.lower())
    if not files:
        raise SystemExit(f'No font source for {slug}')
    want = 'bold' if weight >= 700 else 'regular'
    exact = [p for p in files if want in p.name.lower() and '[' not in p.name]
    if exact:
        shutil.copy2(exact[0], out/name)
        continue
    static = [p for p in files if '[' not in p.name]
    if static and weight == 400:
        shutil.copy2(static[0], out/name)
        continue
    var = next((p for p in files if '[' in p.name), files[0])
    font = TTFont(var)
    if 'fvar' in font:
        axes = {a.axisTag: weight for a in font['fvar'].axes if a.axisTag == 'wght'}
        font = instantiateVariableFont(font, axes, inplace=False)
    font.save(out/name)

count = len(list(out.glob('*.ttf')))
print(f'Restored {count} font files')
if count < 38:
    raise SystemExit('Expected at least 38 bundled fonts')
