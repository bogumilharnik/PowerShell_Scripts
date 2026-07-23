Get-ChildItem "F:\RepositoryISCSI" -Recurse -File |
  Where-Object { $_.LastWriteTime.Date -eq [datetime]"2026-07-22" } |
  Sort-Object LastWriteTime |
  Format-Table FullName, LastWriteTime, Length -AutoSize |
  Out-File "$env:USERPROFILE\Desktop\Raport_pliki\pliki_2126-07-22.txt" -Encoding UTF8