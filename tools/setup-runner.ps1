<#
.SYNOPSIS
    Превращает этот компьютер в машину сборки WesiOS.

.DESCRIPTION
    После этого сборки идут здесь, а не на машинах GitHub, и счётчик минут
    закрытого репозитория их не считает — свои раннеры бесплатны.

    Что делает:
      1. проверяет и доставляет чего не хватает (Git, Flutter, компилятор C++,
         при желании — Java и Android SDK);
      2. скачивает раннер GitHub Actions последней версии;
      3. регистрирует его под меткой wesios-laptop;
      4. ставит службой, чтобы работал сам после перезагрузки.

    Запускать ОДИН раз, от имени администратора.

.PARAMETER Token
    Одноразовый код регистрации. Взять здесь:
      репозиторий → Settings → Actions → Runners → New self-hosted runner
      → Windows → строка `./config.cmd --token XXXX` — нужен именно XXXX.
    Живёт час. Это не пароль и не токен доступа: он позволяет только
    подключить раннер и больше ничего.

.PARAMETER Android
    Готовить машину ещё и к сборке Android (Java 17 + Android SDK).
    Без этого ключа Android продолжит собираться на GitHub — он там дешёвый.

.EXAMPLE
    .\setup-runner.ps1 -Token ABCDEFGHIJKLMNOPQRSTUVWXYZ123

.EXAMPLE
    .\setup-runner.ps1 -Token ABCDEF... -Android
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$Repo = 'https://github.com/wesiwer/WesiOS',

    [string]$Label = 'wesios-laptop',

    [string]$Dir = 'C:\actions-runner',

    [switch]$Android
)

$ErrorActionPreference = 'Stop'

function Say($text)  { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    $text"   -ForegroundColor Green }
function Warn($text) { Write-Host "    $text"   -ForegroundColor Yellow }

# ---------------------------------------------------------------- проверки

$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    throw 'Нужны права администратора: правой кнопкой по PowerShell → «Запуск от имени администратора».'
}

if ([Environment]::Is64BitOperatingSystem -eq $false) {
    throw 'Нужна 64-разрядная Windows.'
}

Say 'Проверяю, чего не хватает'

# winget есть во всех поддерживаемых Windows 10/11. Если его нет — ставим
# руками, потому что тихо пропустить установку хуже, чем сказать прямо.
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Warn 'winget не найден. Установите «Установщик приложений» из Microsoft Store и запустите скрипт заново.'
    throw 'Нет winget'
}

function Ensure($name, $id, $probe) {
    if (Get-Command $probe -ErrorAction SilentlyContinue) {
        Ok "$name — уже есть"
        return
    }
    Say "Ставлю $name"
    winget install --id $id --silent --accept-package-agreements --accept-source-agreements
    # PATH обновляется только для новых процессов, поэтому подтягиваем его
    # прямо сейчас — иначе следующая проверка не найдёт только что
    # установленное и скрипт решит, что установка не удалась.
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')
}

Ensure 'Git'     'Git.Git'                  'git'
Ensure 'Flutter' 'Flutter.Flutter'          'flutter'

if ($Android) {
    Ensure 'Java 17' 'Microsoft.OpenJDK.17' 'java'
}

# Компилятор C++ отдельно: winget не умеет проверить, что нужная нагрузка
# («Разработка классических приложений на C++») действительно выбрана, а без
# неё flutter build windows падает на этапе CMake.
Say 'Проверяю компилятор C++'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCpp = $false
if (Test-Path $vswhere) {
    $found = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $hasCpp = -not [string]::IsNullOrWhiteSpace($found)
}
if ($hasCpp) {
    Ok 'Инструменты C++ на месте'
} else {
    Say 'Ставлю Visual Studio Build Tools с нагрузкой C++'
    winget install --id Microsoft.VisualStudio.2022.BuildTools --silent `
        --accept-package-agreements --accept-source-agreements `
        --override '--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    Ok 'Готово'
}

Say 'Проверяю Flutter'
flutter --version
flutter config --enable-windows-desktop | Out-Null

# ------------------------------------------------------------------ раннер

Say 'Скачиваю раннер GitHub Actions'

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Dir

# Версия берётся последняя выпущенная, а не зашитая в скрипт: раннер
# обновляется часто, и просроченная версия отказывается подключаться.
$release = Invoke-RestMethod 'https://api.github.com/repos/actions/runner/releases/latest'
$version = $release.tag_name.TrimStart('v')
$zip = "actions-runner-win-x64-$version.zip"
$url = "https://github.com/actions/runner/releases/download/v$version/$zip"

Ok "Версия $version"
if (-not (Test-Path $zip)) {
    Invoke-WebRequest -Uri $url -OutFile (Join-Path $Dir $zip)
}
Expand-Archive -Path (Join-Path $Dir $zip) -DestinationPath $Dir -Force

Say 'Подключаю раннер к репозиторию'

# Если раннер уже был настроен, сначала отключаем старую регистрацию —
# иначе config.cmd откажется работать, а служба останется от прошлой
# настройки и будет собирать не то.
if (Test-Path (Join-Path $Dir '.runner')) {
    Warn 'Нашёл прежнюю настройку — снимаю её'
    & (Join-Path $Dir 'config.cmd') remove --token $Token 2>$null
}

& (Join-Path $Dir 'config.cmd') `
    --url $Repo `
    --token $Token `
    --name "$env:COMPUTERNAME-wesios" `
    --labels $Label `
    --work '_work' `
    --unattended `
    --replace `
    --runasservice

if ($LASTEXITCODE -ne 0) {
    throw 'Раннер не подключился. Чаще всего — просроченный код: он живёт час, возьмите новый на странице Runners.'
}

Say 'Запускаю службу'
$svc = Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) {
    Set-Service -Name $svc.Name -StartupType Automatic
    Start-Service -Name $svc.Name
    Ok "Служба $($svc.Name): $((Get-Service $svc.Name).Status)"
} else {
    Warn 'Служба не найдена — раннер можно запустить вручную: .\run.cmd'
}

# ------------------------------------------------------------------- итог

Write-Host ''
Write-Host '================ ГОТОВО ================' -ForegroundColor Green
Write-Host ''
Write-Host 'Остался один шаг, и он на сайте GitHub:'
Write-Host ''
Write-Host '  Settings -> Secrets and variables -> Actions -> Variables -> New variable'
Write-Host ''
Write-Host "     RUNNER_WINDOWS = $Label"
if ($Android) {
    Write-Host "     RUNNER_LINUX   = $Label"
} else {
    Write-Host '     (RUNNER_LINUX не заводите — Android пусть собирается на GitHub, он там дешёвый)'
}
Write-Host ''
Write-Host 'Проверить, что раннер виден: Settings -> Actions -> Runners, зелёная точка Idle.'
Write-Host 'Вернуть сборку на GitHub: стереть переменную. Раннер при этом можно не трогать.'
Write-Host ''
Write-Host 'ВАЖНО: держите репозиторий закрытым.' -ForegroundColor Yellow
Write-Host 'На открытом репозитории свой раннер — дыра: любой может прислать' -ForegroundColor Yellow
Write-Host 'изменение, и его код выполнится на этом компьютере.' -ForegroundColor Yellow
Write-Host ''
