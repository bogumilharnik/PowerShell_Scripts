<#
===============================================================================
    Nazwa      : Export-VeeamConfig.ps1
    Cel        : Wyeksportowanie pelnej konfiguracji systemu Veeam Backup &
                 Replication do pliku TXT - jako dokumentacja stanu faktycznego.
                 Obejmuje:
                   - naglowek (data, serwer, uzytkownik, wersja Veeam),
                   - GLOBALNE ustawienia powiadomien e-mail (SMTP, From, To,
                     Subject, Notify on Success/Warning/Failure),
                   - WSZYSTKIE zadania backup'owe (VM / Agent / Tasmowe) wraz z
                     ustawieniami powiadomien kazdego zadania,
                   - repozytoria backup'owe.

    Uruchomienie (na serwerze Veeam B&R, PowerShell "jako administrator"):
        powershell -ExecutionPolicy Bypass -File .\Export-VeeamConfig.ps1

        Opcjonalnie mozna wskazac wlasna sciezke pliku wyjsciowego:
        powershell -ExecutionPolicy Bypass -File .\Export-VeeamConfig.ps1 -OutputFile "C:\Dowody\veeam.txt"

    Uwaga: zalecane uruchomienie w Windows PowerShell 5.1 (modul Veeam dziala
           tam najstabilniej). Skrypt jest tylko do ODCZYTU - nie zmienia
           zadnych ustawien systemu.
===============================================================================
#>

param(
    [string]$OutputFile = "$env:USERPROFILE\Desktop\Veeam_Config_Export_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
)

$ErrorActionPreference = 'Continue'
$report = New-Object System.Collections.Generic.List[string]

# --- Funkcje pomocnicze -----------------------------------------------------
function Add-Section {
    param([string]$Title)
    $report.Add("")
    $report.Add(("=" * 100))
    $report.Add("  $Title")
    $report.Add(("=" * 100))
    $report.Add("")
    Write-Host ""
    Write-Host "==> $Title" -ForegroundColor Cyan
}

function Add-Text {
    param([string]$Text)
    if ($null -eq $Text) { $Text = "" }
    $report.Add($Text.TrimEnd())
}

function Dump-Object {
    # Zrzuca obiekt w formie Format-List * (Out-String), bezpiecznie.
    param($InputObject, [string]$Label = "")
    if ($Label) { Add-Text ">> $Label" }
    try {
        $s = ($InputObject | Format-List * | Out-String)
        if ([string]::IsNullOrWhiteSpace($s)) { $s = "(brak danych / obiekt pusty)" }
        Add-Text $s
    } catch {
        Add-Text "   (nie udalo sie zrzucic obiektu: $($_.Exception.Message))"
    }
}

# --- NAGLOWEK ---------------------------------------------------------------
Add-Section "NAGLOWEK RAPORTU"
Add-Text ("Data wygenerowania : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Text ("Serwer             : " + $env:COMPUTERNAME)
Add-Text ("Uzytkownik         : " + $env:USERDOMAIN + "\" + $env:USERNAME)

# Zaladowanie modulu Veeam (v11+ = modul, starsze = snap-in)
try {
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    Add-Text "Modul PowerShell   : Veeam.Backup.PowerShell (zaladowany)"
} catch {
    try {
        Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
        Add-Text "Modul PowerShell   : VeeamPSSnapIn (snap-in, starsza wersja)"
    } catch {
        Add-Text "BLAD: Nie udalo sie zaladowac modulu Veeam PowerShell. $($_.Exception.Message)"
        Add-Text "      Uruchom skrypt na serwerze Veeam B&R z zainstalowana konsola."
    }
}

# Wersja Veeam (z rejestru)
try {
    $ver = Get-ItemProperty 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -ErrorAction Stop
    $verString = $ver.CorePackageVersion
    if (-not $verString) { $verString = $ver.UIVersion }
    if (-not $verString) { $verString = $ver.PackageVersion }
    Add-Text ("Wersja Veeam B&R   : " + $verString)
} catch {
    Add-Text "Wersja Veeam B&R   : (nie udalo sie odczytac z rejestru)"
}

# Polaczenie z lokalnym serwerem VBR
try {
    Connect-VBRServer -Server localhost -ErrorAction Stop
    Add-Text "Polaczenie z VBR   : localhost (OK)"
} catch {
    Add-Text "Polaczenie z VBR   : $($_.Exception.Message)"
}

# --- GLOBALNE POWIADOMIENIA -------------------------------------------------
Add-Section "GLOBALNE USTAWIENIA POWIADOMIEN E-MAIL (POZIOM SERWERA)"
$globalDone = $false
try {
    $mail = Get-VBRMailNotificationConfiguration -ErrorAction Stop
    Dump-Object $mail "Get-VBRMailNotificationConfiguration"
    $globalDone = $true
} catch {
    Add-Text "Cmdlet Get-VBRMailNotificationConfiguration niedostepny: $($_.Exception.Message)"
}
if (-not $globalDone) {
    # Proba alternatywna dla starszych wersji
    try {
        $mail2 = Get-VBRNotificationOptions -ErrorAction Stop
        Dump-Object $mail2 "Get-VBRNotificationOptions (starsza wersja)"
        $globalDone = $true
    } catch {
        Add-Text "Alternatywny cmdlet rowniez niedostepny: $($_.Exception.Message)"
        Add-Text "Ustawienia globalne widoczne sa w konsoli: Options > E-mail Settings (zrzut ekranu w dokumentacji)."
    }
}

# --- WSZYSTKIE ZADANIA (Get-VBRJob: VM + czesto tez Agent server-managed) ----
Add-Section "ZADANIA BACKUP'OWE - WSZYSTKIE (Get-VBRJob)"
try {
    $jobs = @(Get-VBRJob -ErrorAction Stop | Sort-Object Name)
    Add-Text ("Liczba zadan (Get-VBRJob): " + $jobs.Count)
    Add-Text ""
    Add-Text (($jobs | Select-Object Name,
                                     JobType,
                                     @{n='Wlaczone';e={ -not $_.IsDisabled }},
                                     @{n='HarmonogramAktywny';e={ $_.IsScheduleEnabled }} |
              Format-Table -AutoSize | Out-String))

    foreach ($job in $jobs) {
        Add-Text ("-" * 100)
        Add-Text ("ZADANIE : " + $job.Name)
        Add-Text ("Typ     : " + $job.JobType)
        Add-Text ("Opis    : " + $job.Description)
        Add-Text ("Wlaczone: " + (-not $job.IsDisabled))
        Add-Text ""

        # Opcje zadania -> USTAWIENIA POWIADOMIEN (kluczowe dla sprawy)
        $opt = $null
        try { $opt = Get-VBRJobOptions -Job $job -ErrorAction Stop } catch {
            try { $opt = $job.GetOptions() } catch { $opt = $null }
        }
        if ($opt -and $opt.NotificationOptions) {
            Dump-Object $opt.NotificationOptions "USTAWIENIA POWIADOMIEN ZADANIA (NotificationOptions)"
        } else {
            Add-Text "   (nie udalo sie odczytac NotificationOptions dla tego zadania)"
        }

        # Harmonogram zadania
        try {
            Dump-Object $job.ScheduleOptions "HARMONOGRAM (ScheduleOptions)"
        } catch { }
    }
} catch {
    Add-Text "Blad Get-VBRJob: $($_.Exception.Message)"
}

# --- ZADANIA AGENTOWE (Computer Backup) -------------------------------------
Add-Section "ZADANIA AGENTOWE / COMPUTER BACKUP (Get-VBRComputerBackupJob)"
try {
    $agentJobs = @(Get-VBRComputerBackupJob -ErrorAction Stop)
    Add-Text ("Liczba zadan agentowych: " + $agentJobs.Count)
    foreach ($aj in $agentJobs) {
        Add-Text ("-" * 100)
        Add-Text ("ZADANIE AGENTOWE : " + $aj.Name)
        Dump-Object $aj "Pelne ustawienia zadania"
    }
    if ($agentJobs.Count -eq 0) {
        Add-Text "Brak zadan tego typu lub wszystkie widoczne juz w sekcji Get-VBRJob."
    }
} catch {
    Add-Text "Cmdlet Get-VBRComputerBackupJob niedostepny w tej wersji: $($_.Exception.Message)"
    Add-Text "Zadania agentowe zarzadzane przez serwer moga byc widoczne w sekcji Get-VBRJob (typ EpAgentBackup)."
}

# --- ZADANIA TASMOWE (Tape Backup) ------------------------------------------
Add-Section "ZADANIA TASMOWE / TAPE BACKUP (Get-VBRTapeJob)"
try {
    $tapeJobs = @(Get-VBRTapeJob -ErrorAction Stop)
    Add-Text ("Liczba zadan tasmowych: " + $tapeJobs.Count)
    foreach ($tj in $tapeJobs) {
        Add-Text ("-" * 100)
        Add-Text ("ZADANIE TASMOWE : " + $tj.Name)
        Add-Text ("Typ             : " + $tj.Type)
        Add-Text ("Wlaczone        : " + $tj.Enabled)
        if ($tj.NotificationOptions) {
            Dump-Object $tj.NotificationOptions "USTAWIENIA POWIADOMIEN ZADANIA TASMOWEGO (NotificationOptions)"
        } else {
            Dump-Object $tj "Pelne ustawienia zadania tasmowego"
        }
    }
    if ($tapeJobs.Count -eq 0) { Add-Text "Brak zadan tasmowych." }
} catch {
    Add-Text "Cmdlet Get-VBRTapeJob niedostepny lub blad: $($_.Exception.Message)"
}

# --- WYNIKI OSTATNICH URUCHOMIEN ZADAN ---------------------------------------
Add-Section "WYNIKI OSTATNICH URUCHOMIEN ZADAN"
try {
    $jobs2 = @(Get-VBRJob -ErrorAction Stop | Sort-Object Name)
    $rows = foreach ($j in $jobs2) {
        $ls = $null
        try { $ls = $j.FindLastSession() } catch { }
        [pscustomobject]@{
            Zadanie      = $j.Name
            Typ          = $j.JobType
            OstatniWynik = $(try { $j.GetLastResult() } catch { "(b/d)" })
            OstatniStan  = $(try { $j.GetLastState() }  catch { "(b/d)" })
            Poczatek     = if ($ls) { $ls.CreationTime } else { $null }
            Koniec       = if ($ls) { $ls.EndTime }      else { $null }
        }
    }
    Add-Text (($rows | Format-Table -AutoSize | Out-String))
} catch {
    Add-Text "Blad pobierania ostatnich wynikow zadan: $($_.Exception.Message)"
}

# Ostatnie wyniki zadan tasmowych
try {
    $tj2 = @(Get-VBRTapeJob -ErrorAction SilentlyContinue)
    if ($tj2.Count -gt 0) {
        Add-Text ">> Ostatnie wyniki zadan tasmowych:"
        Add-Text (($tj2 | Select-Object Name, LastResult, LastState, NextRun |
                   Format-Table -AutoSize | Out-String))
    }
} catch { }

# --- HISTORIA SESJI Z OSTATNICH 30 DNI ---------------------------------------
Add-Section "HISTORIA SESJI BACKUP'OWYCH Z OSTATNICH 30 DNI (Get-VBRBackupSession)"
try {
    $since = (Get-Date).AddDays(-30)
    $sessions = @(Get-VBRBackupSession -ErrorAction Stop |
                  Where-Object { $_.CreationTime -ge $since } |
                  Sort-Object CreationTime -Descending)
    Add-Text ("Okres                : od " + $since.ToString('yyyy-MM-dd') + " do dzis")
    Add-Text ("Liczba sesji         : " + $sessions.Count)
    $ok   = @($sessions | Where-Object { $_.Result -eq 'Success' }).Count
    $warn = @($sessions | Where-Object { $_.Result -eq 'Warning' }).Count
    $fail = @($sessions | Where-Object { $_.Result -eq 'Failed'  }).Count
    Add-Text ("  w tym Success      : " + $ok)
    Add-Text ("  w tym Warning      : " + $warn)
    Add-Text ("  w tym Failed       : " + $fail)
    Add-Text ""
    Add-Text (($sessions | Select-Object JobName, CreationTime, EndTime, Result, State |
               Format-Table -AutoSize | Out-String))
} catch {
    Add-Text "Blad Get-VBRBackupSession: $($_.Exception.Message)"
}

# --- REPOZYTORIA ------------------------------------------------------------
Add-Section "REPOZYTORIA BACKUP'OWE"
try {
    $repos = @(Get-VBRBackupRepository -ErrorAction Stop)
    Add-Text ("Liczba repozytoriow (standardowych): " + $repos.Count)
    Add-Text (($repos | Select-Object Name, Type, Path, FriendlyPath, Description |
               Format-List | Out-String))
} catch {
    Add-Text "Blad Get-VBRBackupRepository: $($_.Exception.Message)"
}
try {
    $sobr = @(Get-VBRBackupRepository -ScaleOut -ErrorAction Stop)
    if ($sobr.Count -gt 0) {
        Add-Text ("Repozytoria Scale-Out (SOBR): " + $sobr.Count)
        Add-Text (($sobr | Select-Object Name, Description | Format-List | Out-String))
    }
} catch { }

# --- ZAKONCZENIE ------------------------------------------------------------
Add-Section "KONIEC RAPORTU"
Add-Text ("Raport wygenerowano: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

try {
    $report | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "Zapisano raport do pliku:" -ForegroundColor Green
    Write-Host "    $OutputFile" -ForegroundColor Green
} catch {
    Write-Host "BLAD zapisu pliku: $($_.Exception.Message)" -ForegroundColor Red
}

try { Disconnect-VBRServer -ErrorAction SilentlyContinue } catch { }
