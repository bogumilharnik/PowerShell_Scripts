#Requires -Version 5.1
<#
================================================================================
  Set-KioskDisplay.ps1
  1) Obraca ekran do pionu (portrait).
  2) Calkowicie wylacza wygaszanie/uspienie ekranu - lacznie z ukrytym
     "console lock display off timeout", ktory wygasza ekran na ekranie
     blokady/logowania mimo monitor-timeout=0.
  3) Wylacza wygaszacz ekranu dla konta Kiosk.
  Windows 11 (w tym 25H2).

  Uruchom jako Administrator, w sesji INTERAKTYWNEJ (nie przez zadanie SYSTEM):
    powershell -ExecutionPolicy Bypass -File .\Set-KioskDisplay.ps1
  Domyslnie pion = obrot 90 st. Jesli ekran wyjdzie "do gory nogami":
    ... -Orientation portrait-flipped
================================================================================
#>
param(
    [ValidateSet("portrait","portrait-flipped","landscape","landscape-flipped")]
    [string] $Orientation = "portrait",
    [string] $KioskUser    = "" # nazwa konta, dla ktorego wylaczany jest wygaszacz ekranu
)

$ErrorActionPreference = "Stop"
function Write-Step($n,$m){ Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-OK($m){ Write-Host "    OK  - $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    !   - $m" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) { Write-Host "Uruchom ten skrypt jako Administrator." -ForegroundColor Red; exit 1 }

Write-Host "================ EKRAN KIOSKU: PION + BEZ WYGASZANIA ================" -ForegroundColor White

# ---------------------------------------------------------------------------
# 1) Obrot ekranu
# ---------------------------------------------------------------------------
Write-Step 1 "Obracanie ekranu: $Orientation"
$code = @'
using System;
using System.Runtime.InteropServices;
public class KioskDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX; public int dmPositionY;
        public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency;
        public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
        public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }
    [DllImport("user32.dll")] public static extern int EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int CDS_UPDATEREGISTRY = 0x01;
    public const int DM_PELSWIDTH = 0x00080000, DM_PELSHEIGHT = 0x00100000, DM_DISPLAYORIENTATION = 0x00000080;
    public static int Rotate(int orientation) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm) == 0) return -99;
        bool curPortrait = (dm.dmDisplayOrientation == 1 || dm.dmDisplayOrientation == 3);
        bool tgtPortrait = (orientation == 1 || orientation == 3);
        if (curPortrait != tgtPortrait) { int t = dm.dmPelsWidth; dm.dmPelsWidth = dm.dmPelsHeight; dm.dmPelsHeight = t; }
        dm.dmDisplayOrientation = orientation;
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYORIENTATION;
        return ChangeDisplaySettings(ref dm, CDS_UPDATEREGISTRY);
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'KioskDisplay').Type) { Add-Type -TypeDefinition $code }
$map = @{ "landscape" = 0; "portrait" = 1; "landscape-flipped" = 2; "portrait-flipped" = 3 }
$res = [KioskDisplay]::Rotate($map[$Orientation])
if ($res -eq 0) { Write-OK "Ekran obrocony: $Orientation (zapisane, utrzyma sie po restarcie)." }
else { Write-Warn2 "Obrot zwrocil kod $res. Jesli ekran sie nie obrocil lub jest 'do gory nogami', sprobuj -Orientation portrait-flipped." }

# ---------------------------------------------------------------------------
# 2) Zero wygaszania / uspienia / usypiania dyskow + console lock timeout
# ---------------------------------------------------------------------------
Write-Step 2 "Wylaczanie wygaszania i uspienia ekranu"
$HighPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
powercfg /setactive $HighPerf 2>$null
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change disk-timeout-ac    0
powercfg /change disk-timeout-dc    0
# ukryty: "console lock display off timeout" (wygasza ekran na ekranie blokady)
$SUB_VIDEO    = "7516b95f-f776-4464-8c53-06167f40cc99"
$VIDEOCONLOCK = "8ec4b3a5-6868-48c2-be75-4f3044be88a7"
powercfg /setacvalueindex SCHEME_CURRENT $SUB_VIDEO $VIDEOCONLOCK 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_VIDEO $VIDEOCONLOCK 0
powercfg /setactive SCHEME_CURRENT 2>$null
Write-OK "Wygaszanie ekranu, uspienie i console-lock-timeout: nigdy."

# ---------------------------------------------------------------------------
# 3) Wylaczenie wygaszacza ekranu dla konta Kiosk
# ---------------------------------------------------------------------------
Write-Step 3 "Wylaczanie wygaszacza ekranu dla konta '$KioskUser'"
function Disable-Screensaver([string]$deskKey) {
    reg add "$deskKey" /v ScreenSaveActive    /t REG_SZ /d 0 /f | Out-Null
    reg add "$deskKey" /v ScreenSaveTimeOut   /t REG_SZ /d 0 /f | Out-Null
    reg add "$deskKey" /v ScreenSaverIsSecure /t REG_SZ /d 0 /f | Out-Null
    reg delete "$deskKey" /v "SCRNSAVE.EXE" /f 2>$null | Out-Null
}
$kioskSid = $null
try { $kioskSid = (Get-LocalUser -Name $KioskUser).SID.Value } catch {}
if ($kioskSid -and (Test-Path "Registry::HKEY_USERS\$kioskSid")) {
    # konto Kiosk jest aktualnie zalogowane - rejestr juz zaladowany
    Disable-Screensaver "HKEY_USERS\$kioskSid\Control Panel\Desktop"
    Write-OK "Wygaszacz wylaczony (konto '$KioskUser' zalogowane)."
} elseif (Test-Path "C:\Users\$KioskUser\NTUSER.DAT") {
    reg load "HKU\KioskTmp" "C:\Users\$KioskUser\NTUSER.DAT" | Out-Null
    Disable-Screensaver "HKU\KioskTmp\Control Panel\Desktop"
    [gc]::Collect(); Start-Sleep -Milliseconds 500
    reg unload "HKU\KioskTmp" | Out-Null
    Write-OK "Wygaszacz wylaczony (profil '$KioskUser')."
} else {
    Write-Warn2 "Profil konta '$KioskUser' jeszcze nie istnieje - uruchom skrypt po pierwszym logowaniu Kiosk."
}

Write-Host "`n================ GOTOWE ================" -ForegroundColor White
Write-Host "Ekran w pionie, wygaszanie i wygaszacz wylaczone." -ForegroundColor White
Write-Host "Jesli ekran jest obrocony w zla strone: uruchom z -Orientation portrait-flipped." -ForegroundColor White
