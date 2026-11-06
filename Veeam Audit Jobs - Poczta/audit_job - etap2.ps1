
# AUDYT POCZTA - ETAP 2
# READ-ONLY: tylko nazwy i rozmiary plikow
# Nie oblicza SHA256 i nie modyfikuje repozytorium

$ErrorActionPreference = 'Stop'

$folder = 'F:\RepositoryISCSI\Poczta'
$csv = 'C:\Users\Administrator\Desktop\2026-10-26-SHA256_Poczta.csv'

$expected = @(Import-Csv -LiteralPath $csv -Delimiter ';')
$actual = @(Get-ChildItem -LiteralPath $folder -File -Force)

Write-Host "`n=== LICZBA PLIKOW ==="
Write-Host "Manifest: $($expected.Count)"
Write-Host "Katalog:  $($actual.Count)"

# Petla foreach zapisuje wyniki do zmiennej
$report = @(
    foreach ($item in $actual) {

        $matches = @(
            $expected | Where-Object {
                $_.Name -ceq $item.Name
            }
        )

        $sizeOK = $false

        if ($matches.Count -eq 1) {
            $sizeOK = (
                $item.Length -eq [long]$matches[0].LengthBytes
            )
        }

        [PSCustomObject]@{
            Name        = $item.Name
            InManifest  = ($matches.Count -eq 1)
            SizeMatches = $sizeOK
            LengthBytes = $item.Length
        }
    }
)

Write-Host "`n=== PLIKI W KATALOGU ==="

$report | Format-Table -AutoSize

$missing = @(
    foreach ($item in $expected) {
        $name = $item.Name

        if (-not @(
            $actual | Where-Object {
                $_.Name -ceq $name
            }
        ).Count) {
            $name
        }
    }
)

$unexpected = @(
    $report | Where-Object {
        -not $_.InManifest
    }
)

$wrongSize = @(
    $report | Where-Object {
        -not $_.SizeMatches
    }
)

$duplicateManifest = @(
    $expected |
        Group-Object Name |
        Where-Object Count -gt 1
)

Write-Host "`n=== PODSUMOWANIE ==="

[PSCustomObject]@{
    ManifestFiles     = $expected.Count
    DirectoryFiles    = $actual.Count
    MissingFiles      = $missing.Count
    UnexpectedFiles   = $unexpected.Count
    WrongSize         = $wrongSize.Count
    DuplicateManifest = $duplicateManifest.Count
} | Format-List

if (
    $expected.Count -eq 10 -and
    $actual.Count -eq 10 -and
    $missing.Count -eq 0 -and
    $unexpected.Count -eq 0 -and
    $wrongSize.Count -eq 0 -and
    $duplicateManifest.Count -eq 0
) {
    Write-Host "WYNIK: ZGODNOSC NAZW I ROZMIAROW 10/10"
} else {
    Write-Warning "WYNIK: WYMAGA WYJASNIENIA"
}
