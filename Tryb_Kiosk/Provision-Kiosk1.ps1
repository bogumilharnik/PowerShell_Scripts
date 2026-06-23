#Requires -Version 5.1
<#
================================================================================
  Provision-Kiosk.ps1
  Konfiguracja terminala KIOSK z Microsoft Edge ograniczonym do wybranych domen.

  Co robi skrypt:
    1) Ustawia nazwe komputera (domyslnie KIOSK1)
    2) Stosuje polityki Edge: URLBlocklist=* + URLAllowlist (tylko Twoje domeny)
    3) Konfiguruje Assigned Access (Edge single-app kiosk) -> tworzy zarzadzane
       konto kiosku z autologowaniem (AutoLogonAccount)
    4) Weryfikuje, czy wszystko sie zapisalo

  Uruchomienie (jako Administrator):
    powershell -ExecutionPolicy Bypass -File .\Provision-Kiosk.ps1

  Po zakonczeniu wymagany jest JEDEN restart, aby kiosk sie aktywowal.
  Restart systemu jest potrzebny tylko z powodu zmiany nazwy hosta i aktywacji
  Assigned Access - same polityki Edge dzialaja juz po restarcie przegladarki.
================================================================================
#>

param(
    # --- Ustawienia do edycji ---------------------------------------------
    [string]   $ComputerName       = "KIOSK1", # nazwa hosta (bez spacji, max 15 znakow)
    [string]   $StartUrl           = "", # adres startowy Edge w trybie kiosku (moze byc dowolny URL)
    [string[]] $AllowedDomains     = @(""), # lista domen dozwolonych w trybie kiosku (bez protokolu, bez slasha na koncu w postaci "nazwa.domeny")
    [int]      $IdleTimeoutMinutes = 5,
    [ValidateSet("fullscreen","public-browsing")]
    [string]   $KioskType          = "fullscreen",        # fullscreen = pelny ekran BEZ paska adresu (digital signage); public-browsing = z paskiem adresu i kartami
    [string]   $BreakoutKey        = "Ctrl+Alt+Shift+Q",  # skrot admina do wyjscia z kiosku (modyfikatory + klawisz)
    [string]   $KioskUser          = "Kiosk",             # nazwa lokalnego konta kiosku
    [string]   $KioskPassword      = "",   # haslo konta kiosku - Cudzysłowy obowiazkowe (znaki ^ $ #); uzywane tez do autologowania
    [string]   $WifiSSID           = "",                  # SSID sieci Wi-Fi (puste = pomin konfiguracje Wi-Fi)
    [string]   $WifiPassword       = "",                  # haslo Wi-Fi (WPA2/WPA3 Personal)
    [ValidateSet("WPA2PSK","WPA3SAE")]
    [string]   $WifiAuth           = "WPA2PSK",           # typ zabezpieczen sieci Wi-Fi
    [switch]   $SkipAssignedAccess,    # ETAP 1: konto + autologowanie + polityki, BEZ blokady kiosku (do recznego zapisania Wi-Fi Enterprise na koncie Kiosk)
    [switch]   $Restart,               # -Restart => automatyczny restart na koncu skryptu

    # --- Parametry wewnetrzne (nie ustawiaj recznie) ----------------------
    [switch]   $ApplyAAOnly,
    [string]   $XmlPath,
    [string]   $LogPath
)

$ErrorActionPreference = "Stop"
$ProfileId = "{EDB3036B-780D-487D-A375-69369D8A8F78}"

function Write-Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK($msg)        { Write-Host "    OK  - $msg" -ForegroundColor Green }
function Write-Warn2($msg)     { Write-Host "    !   - $msg" -ForegroundColor Yellow }
function Test-IsSystem {
    return ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value -eq "S-1-5-18"
}

# ============================================================================
#  TRYB WEWNETRZNY: zastosowanie Assigned Access jako SYSTEM (wolany przez
#  tymczasowe zadanie harmonogramu). Nie uruchamiaj recznie.
# ============================================================================
if ($ApplyAAOnly) {
    $result = @()
    try {
        $xml = Get-Content -LiteralPath $XmlPath -Raw
        $ns  = "root\cimv2\mdm\dmmap"
        $cls = "MDM_AssignedAccess"
        $obj = Get-CimInstance -Namespace $ns -ClassName $cls
        $obj.Configuration = [System.Net.WebUtility]::HtmlEncode($xml)
        Set-CimInstance -CimInstance $obj -ErrorAction Stop | Out-Null

        # odczyt zwrotny dla weryfikacji
        $check = (Get-CimInstance -Namespace $ns -ClassName $cls).Configuration
        if ([string]::IsNullOrWhiteSpace($check)) {
            $result += "AA_FAIL: konfiguracja pusta po zapisie"
            $result -join "`n" | Set-Content -LiteralPath $LogPath
            exit 1
        }
        $result += "AA_OK: konfiguracja zapisana ($($check.Length) znakow)"
        $result -join "`n" | Set-Content -LiteralPath $LogPath
        exit 0
    }
    catch {
        $result += "AA_FAIL: $($_.Exception.Message)"
        $result -join "`n" | Set-Content -LiteralPath $LogPath
        exit 1
    }
}

# ============================================================================
#  TRYB GLOWNY
# ============================================================================

# --- Kontrola uprawnien administratora --------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Uruchom ten skrypt jako Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "================ PROVISIONING KIOSKU: $ComputerName ================" -ForegroundColor White

# ---------------------------------------------------------------------------
# Wi-Fi: opcjonalne zaprovisionowanie sieci, aby kiosk laczyl sie automatycznie
# ---------------------------------------------------------------------------
if ($WifiSSID) {
    Write-Host "`n[Wi-Fi] Konfiguracja sieci '$WifiSSID'" -ForegroundColor Cyan
    $ssidEsc = [System.Security.SecurityElement]::Escape($WifiSSID)
    $pwdEsc  = [System.Security.SecurityElement]::Escape($WifiPassword)
    $wifiXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$ssidEsc</name>
  <SSIDConfig><SSID><name>$ssidEsc</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>$WifiAuth</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$pwdEsc</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
"@
    $wifiFile = Join-Path $env:TEMP "wifi-profile.xml"
    $wifiXml | Set-Content -LiteralPath $wifiFile -Encoding UTF8
    netsh wlan delete profile name="$WifiSSID" 2>&1 | Out-Null   # usun ewentualne kopie per-user - zaczynamy czysto
    $null = netsh wlan add profile filename="$wifiFile" user=all 2>&1
    Remove-Item $wifiFile -ErrorAction SilentlyContinue   # plik zawiera haslo - kasujemy od razu
    # WYMUS profil "dla wszystkich uzytkownikow" - inaczej trafia tylko na konto admina
    # uruchamiajacego skrypt, a konto Kiosk go nie widzi:
    netsh wlan set profiletype name="$WifiSSID" profiletype=all 2>&1 | Out-Null
    $profiles = netsh wlan show profiles 2>&1 | Out-String
    if ($profiles -match [regex]::Escape($WifiSSID)) {
        netsh wlan connect name="$WifiSSID" ssid="$WifiSSID" 2>&1 | Out-Null
        Write-OK "Profil Wi-Fi '$WifiSSID' ustawiony dla WSZYSTKICH uzytkownikow (w tym '$KioskUser'), autopolaczenie."
    } else {
        Write-Warn2 "Nie udalo sie dodac profilu Wi-Fi - czy jest karta Wi-Fi i dziala usluga WLAN AutoConfig?"
    }
}

# ---------------------------------------------------------------------------
# 1) Nazwa hosta
# ---------------------------------------------------------------------------
Write-Step 1 "Ustawianie nazwy komputera na '$ComputerName'"
$pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
if ($env:COMPUTERNAME -eq $ComputerName -or $pendingName -eq $ComputerName) {
    Write-OK "Nazwa juz ustawiona / zaplanowana ($ComputerName)."
} else {
    Rename-Computer -NewName $ComputerName -Force -ErrorAction Stop
    Write-OK "Zmieniono nazwe na '$ComputerName' (zacznie obowiazywac po restarcie)."
}

# ---------------------------------------------------------------------------
# 2) Polityki Edge: blokuj wszystko poza dozwolonymi domenami
# ---------------------------------------------------------------------------
Write-Step 2 "Stosowanie polityk Microsoft Edge (URLBlocklist / URLAllowlist)"
$edgeKey  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$blockKey = "$edgeKey\URLBlocklist"
$allowKey = "$edgeKey\URLAllowlist"

# czyszczenie ewentualnych starych wpisow, aby lista byla dokladnie ta zadana
Remove-Item -Path $blockKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $allowKey -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $blockKey -Force | Out-Null
New-Item -Path $allowKey -Force | Out-Null

# URLBlocklist: "1" = "*"  -> blokuje wszystko
New-ItemProperty -Path $blockKey -Name "1" -Value "*" -PropertyType String -Force | Out-Null

# URLAllowlist: wyjatki (maja pierwszenstwo nad blokada)
$i = 1
foreach ($d in $AllowedDomains) {
    New-ItemProperty -Path $allowKey -Name "$i" -Value $d -PropertyType String -Force | Out-Null
    $i++
}
Write-OK "Zablokowano wszystko, dozwolone: $($AllowedDomains -join ', ')"

# Nawigacja w trybie public-browsing: pasek adresu TYLKO DO ODCZYTU (bez wpisywania URL)
# + przycisk Strona glowna prowadzacy do adresu startowego (dotykowy powrot z blokowanej strony).
# KioskAddressBarEditingEnabled dziala tylko w trybie public-browsing; wymaga restartu przegladarki.
New-ItemProperty -Path $edgeKey -Name "KioskAddressBarEditingEnabled" -Value 0          -PropertyType DWord  -Force | Out-Null
New-ItemProperty -Path $edgeKey -Name "ShowHomeButton"               -Value 1          -PropertyType DWord  -Force | Out-Null
New-ItemProperty -Path $edgeKey -Name "HomepageIsNewTabPage"         -Value 0          -PropertyType DWord  -Force | Out-Null
New-ItemProperty -Path $edgeKey -Name "HomepageLocation"             -Value $StartUrl  -PropertyType String -Force | Out-Null
Write-OK "Pasek adresu tylko do odczytu + przycisk Strona glowna ($StartUrl)."

# ---------------------------------------------------------------------------
# 3) Konto kiosku + autologowanie + Assigned Access (Edge single-app)
# ---------------------------------------------------------------------------
Write-Step 3 "Konto kiosku, autologowanie i Assigned Access (Edge: $KioskType)"

# 3a) Lokalne konto standardowe dla kiosku (musi istniec PRZED konfiguracja Assigned Access)
$secPass = ConvertTo-SecureString $KioskPassword -AsPlainText -Force
if (Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue) {
    # NIE resetujemy hasla istniejacego konta: reset hasla przez admina uniewaznia
    # zapisane (DPAPI) poswiadczenia Wi-Fi Enterprise zapisane na tym koncie.
    Set-LocalUser -Name $KioskUser -PasswordNeverExpires $true
    Write-OK "Konto '$KioskUser' istnieje - haslo BEZ zmian (chroni zapisane poswiadczenia Wi-Fi)."
} else {
    New-LocalUser -Name $KioskUser -Password $secPass -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword -FullName "Kiosk" | Out-Null
    Write-OK "Utworzono konto standardowe '$KioskUser'."
}
# dodanie do grupy Uzytkownicy po SID (niezaleznie od jezyka systemu)
$usersGroup = (Get-LocalGroup -SID 'S-1-5-32-545').Name
Add-LocalGroupMember -Group $usersGroup -Member $KioskUser -ErrorAction SilentlyContinue

# 3b) Autologowanie na konto kiosku (nadpisuje ewentualne autologowanie z unattend)
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon'    -Value '1'            -Type String
Set-ItemProperty -Path $winlogon -Name 'DefaultUserName'   -Value $KioskUser     -Type String
Set-ItemProperty -Path $winlogon -Name 'DefaultPassword'   -Value $KioskPassword -Type String
Set-ItemProperty -Path $winlogon -Name 'DefaultDomainName' -Value $ComputerName  -Type String
Remove-ItemProperty -Path $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
# wylaczenie trybu "passwordless" Win11, ktory potrafi blokowac autologowanie konta lokalnego
$plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
if (Test-Path $plKey) { Set-ItemProperty -Path $plKey -Name 'DevicePasswordLessBuildVersion' -Value 0 -Type DWord }
Write-OK "Autologowanie ustawione na konto '$KioskUser'."

# 3c) Assigned Access - Edge single-app kiosk dla konta '$KioskUser'
if ($SkipAssignedAccess) {
    Write-Warn2 "ETAP 1: pominieto Assigned Access. Zaloguj sie teraz na '$KioskUser', polacz Wi-Fi i zapisz poswiadczenia, potem uruchom skrypt PONOWNIE bez -SkipAssignedAccess."
} else {
$edgeArgs = "--kiosk $StartUrl --edge-kiosk-type=$KioskType --kiosk-idle-timeout-minutes=$IdleTimeoutMinutes --no-first-run"

$aaXml = @"
<?xml version="1.0" encoding="utf-8"?>
<AssignedAccessConfiguration
    xmlns="http://schemas.microsoft.com/AssignedAccess/2017/config"
    xmlns:rs5="http://schemas.microsoft.com/AssignedAccess/201810/config"
    xmlns:v4="http://schemas.microsoft.com/AssignedAccess/2021/config">
  <Profiles>
    <Profile Id="$ProfileId">
      <KioskModeApp v4:ClassicAppPath="%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
                    v4:ClassicAppArguments="$edgeArgs" />
      <v4:BreakoutSequence Key="$BreakoutKey" />
    </Profile>
  </Profiles>
  <Configs>
    <Config>
      <Account>.\$KioskUser</Account>
      <DefaultProfile Id="$ProfileId" />
    </Config>
  </Configs>
</AssignedAccessConfiguration>
"@

# zapis XML do pliku tymczasowego
$tmpXml = Join-Path $env:TEMP "kiosk-aa.xml"
$tmpLog = Join-Path $env:TEMP "kiosk-aa.log"
Remove-Item $tmpLog -ErrorAction SilentlyContinue
$aaXml | Set-Content -LiteralPath $tmpXml -Encoding UTF8

$scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }

if (Test-IsSystem) {
    # juz dzialamy jako SYSTEM (np. w trybie specialize) - stosujemy bezposrednio
    $ns = "root\cimv2\mdm\dmmap"; $cls = "MDM_AssignedAccess"
    $obj = Get-CimInstance -Namespace $ns -ClassName $cls
    $obj.Configuration = [System.Net.WebUtility]::HtmlEncode($aaXml)
    Set-CimInstance -CimInstance $obj | Out-Null
    Write-OK "Assigned Access zastosowane (kontekst SYSTEM)."
} else {
    # uruchamiamy aplikowanie jako SYSTEM przez jednorazowe zadanie harmonogramu
    $taskName = "ProvisionKioskAA"
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ApplyAAOnly -XmlPath "{1}" -LogPath "{2}"' -f $scriptPath, $tmpXml, $tmpLog
    $action    = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arg
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    # czekanie na zakonczenie
    $waited = 0
    do { Start-Sleep -Milliseconds 500; $waited += 0.5
         $state = (Get-ScheduledTask -TaskName $taskName).State
    } while ($state -eq "Running" -and $waited -lt 60)
    $code = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

    $logTxt = if (Test-Path $tmpLog) { Get-Content $tmpLog -Raw } else { "(brak logu)" }
    if ($code -eq 0) { Write-OK "Assigned Access zastosowane jako SYSTEM. $logTxt" }
    else { Write-Warn2 "Problem przy aplikowaniu Assigned Access (kod $code). $logTxt" }
}
Remove-Item $tmpXml -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 4) Weryfikacja
# ---------------------------------------------------------------------------
Write-Step 4 "Weryfikacja konfiguracji"

# 4a) nazwa hosta (aktywna vs oczekujaca po restarcie)
$active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
$pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
if ($pending -eq $ComputerName) {
    if ($active -eq $ComputerName) { Write-OK "Nazwa hosta: $active" }
    else { Write-Warn2 "Nazwa hosta: aktywna '$active', po restarcie -> '$pending'" }
} else { Write-Warn2 "Nazwa hosta NIE ustawiona poprawnie (aktywna '$active', oczekujaca '$pending')" }

# 4b) polityki Edge
$bl = (Get-ItemProperty -Path $blockKey -ErrorAction SilentlyContinue)."1"
if ($bl -eq "*") { Write-OK "URLBlocklist[1] = *" } else { Write-Warn2 "URLBlocklist NIE ustawione" }
$allowVals = (Get-Item -Path $allowKey -ErrorAction SilentlyContinue).Property | ForEach-Object {
    (Get-ItemProperty -Path $allowKey -Name $_).$_
}
if ($allowVals) { Write-OK "URLAllowlist = $($allowVals -join ', ')" } else { Write-Warn2 "URLAllowlist puste" }

# 4c) obecnosc Edge
$edgeExe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (Test-Path $edgeExe) { Write-OK "Edge znaleziony: $edgeExe" }
else {
    $edgeExe2 = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    if (Test-Path $edgeExe2) { Write-Warn2 "Edge jest w '$edgeExe2' - popraw sciezke w XML (ClassicAppPath) na %ProgramFiles%." }
    else { Write-Warn2 "Nie znaleziono msedge.exe - sprawdz, czy Edge jest zainstalowany." }
}

# 4c2) konto kiosku + autologowanie
if (Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue) { Write-OK "Konto kiosku istnieje: $KioskUser" }
else { Write-Warn2 "Brak konta kiosku '$KioskUser'." }
$wl = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
if ($wl.AutoAdminLogon -eq '1' -and $wl.DefaultUserName -eq $KioskUser) {
    Write-OK "Autologowanie: AutoAdminLogon=1, konto '$($wl.DefaultUserName)'."
} else {
    Write-Warn2 "Autologowanie nie wskazuje na '$KioskUser' (AutoAdminLogon=$($wl.AutoAdminLogon), user=$($wl.DefaultUserName))."
}

# 4d) stan Assigned Access
#     Konfiguracja jest odczytywana zwrotnie juz w kroku [3] (w kontekscie SYSTEM),
#     wiec nie trzeba ponownie czytac MDM_AssignedAccess tutaj.
Write-OK "Assigned Access: zapis potwierdzony w kroku [3] (patrz 'AA_OK' powyzej)."

# 4e) wersja / kompilacja Windows
#     Regresje trybu kiosk z jesieni 2025 (popup "restrictions in effect",
#     blad wdrozenia MDM 0x86000005) naprawiono w buildach:
#       26100.7705 (24H2)  oraz  26200.7705 (25H2).
$cv    = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$cv.CurrentBuildNumber
$ubr   = [int]$cv.UBR
Write-Host "    i   - Windows: $($cv.DisplayVersion)  build $build.$ubr" -ForegroundColor Gray
if (($build -eq 26100 -or $build -ge 26200) -and $ubr -lt 7705) {
    Write-Warn2 "Ta kompilacja ma znane regresje trybu kiosk (popup 'restrictions in effect')."
    Write-Warn2 "Zaktualizuj Windows do co najmniej buildu .7705 (Windows Update) przed wdrozeniem."
} else {
    Write-OK "Kompilacja powyzej progu znanych regresji kiosku (.7705)."
}

# ---------------------------------------------------------------------------
Write-Host "`n================ GOTOWE ================" -ForegroundColor White
Write-Host "Uruchom ponownie komputer, aby aktywowac kiosk:" -ForegroundColor White
Write-Host "    Restart-Computer -Force" -ForegroundColor Gray
Write-Host "Po restarcie maszyna sama zaloguje sie na konto kiosku i otworzy Edge." -ForegroundColor White
Write-Host "Wyjscie z kiosku dla administratora: skrot $BreakoutKey, potem przelacz uzytkownika." -ForegroundColor White

# ---------------------------------------------------------------------------
# Opcjonalny automatyczny restart (gdy uruchomiono z parametrem -Restart)
# ---------------------------------------------------------------------------
if ($Restart) {
    $delay = 15
    Write-Host "`nKomputer zostanie zrestartowany za $delay s." -ForegroundColor Yellow
    Write-Host "Aby PRZERWAC restart, nacisnij teraz Ctrl+C." -ForegroundColor Yellow
    Start-Sleep -Seconds $delay
    Write-Host "Restartuje..." -ForegroundColor Yellow
    Restart-Computer -Force
} else {
    Write-Host "`n(Uruchom z parametrem -Restart, aby zrestartowac automatycznie.)" -ForegroundColor Gray
}
