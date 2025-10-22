# URL-адрес изображения для обоев
$imageUrl = "https://raw.githubusercontent.com/servavox/wallpaper-prank/refs/heads/main/61o07gshhmga1.png"

# Путь для сохранения изображения
$tempPath = "$env:TEMP\wallpaper.jpg"

# Функция для установки обоев
function Set-Wallpaper {
    param (
        [string]$ImagePath
    )
    # Код для установки обоев через Windows API
    $code = @"
    using System;
    using System.Runtime.InteropServices;
    using Microsoft.Win32;
    public class Wallpaper
    {
        public const int SPI_SETDESKWALLPAPER = 20;
        public const int SPIF_UPDATEINIFILE = 0x01;
        public const int SPIF_SENDWININICHANGE = 0x02;
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        public static void Set(string path)
        {
            SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
        }
    }
"@
    Add-Type -TypeDefinition $code
    [Wallpaper]::Set($ImagePath)
}

try {
    # Загрузка изображения
    Invoke-WebRequest -Uri $imageUrl -OutFile $tempPath -ErrorAction Stop

    # Установка обоев
    Set-Wallpaper -ImagePath $tempPath

    Write-Host "Обои успешно изменены."
}
catch {
    Write-Error "Не удалось загрузить или установить обои. Ошибка: $_"
}
