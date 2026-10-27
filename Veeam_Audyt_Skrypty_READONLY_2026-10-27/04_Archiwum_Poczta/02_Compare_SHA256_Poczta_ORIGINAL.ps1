# Read-only CSV comparison; exits non-zero when not all 10 files match.
param(
 [Parameter(Mandatory=$true)][string]$SourceCsv,
 [Parameter(Mandatory=$true)][string]$RestoredCsv
)
$ErrorActionPreference='Stop'
$src=@(Import-Csv -LiteralPath $SourceCsv -Delimiter ';')
$dst=@(Import-Csv -LiteralPath $RestoredCsv -Delimiter ';')
if ($src.Count -ne 10 -or $dst.Count -ne 10) { throw "Expected 10+10 records, got $($src.Count)+$($dst.Count)." }
foreach ($side in @(@{name='SOURCE';rows=$src},@{name='RESTORED';rows=$dst})) {
 $names=@($side.rows | Select-Object -ExpandProperty Name)
 if (@($names | Select-Object -Unique).Count -ne 10) { throw "Duplicate filenames in $($side.name) manifest." }
 foreach ($r in $side.rows) {
  if ([string]::IsNullOrWhiteSpace($r.Name) -or $r.LengthBytes -notmatch '^\d+$' -or $r.SHA256 -notmatch '^[A-Fa-f0-9]{64}$') {
   throw "Invalid record in $($side.name) manifest: $($r.Name)"
  }
 }
}
$map=@{}; foreach($r in $dst){ $map[$r.Name.ToLowerInvariant()]=$r }
$failed=0
foreach($a in ($src | Sort-Object Name)) {
 $b=$map[$a.Name.ToLowerInvariant()]
 $ok=($null -ne $b -and $a.LengthBytes -eq $b.LengthBytes -and $a.SHA256.ToUpperInvariant() -eq $b.SHA256.ToUpperInvariant())
 [pscustomobject]@{File=$a.Name; Result=$(if($ok){'MATCH'}else{'MISMATCH'}); SourceBytes=$a.LengthBytes; RestoredBytes=$(if($b){$b.LengthBytes}else{'MISSING'})} | Format-Table -AutoSize
 if(-not $ok){$failed++}
}
if($failed -gt 0){ throw "FAILED: $failed file(s) inconsistent." }
Write-Host 'PASS: 10/10 filenames, byte lengths and SHA-256 values match.' -ForegroundColor Green
