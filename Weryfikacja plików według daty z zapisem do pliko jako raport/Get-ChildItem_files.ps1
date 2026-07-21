Get-ChildItem "F:\RepositoryISCSI" -Recurse -File |
  Where-Object { $_.LastWriteTime.Date -eq [datetime]"2026-07-21" } |
  Sort-Object LastWriteTime |
  Format-Table FullName, LastWriteTime, Length -AutoSize |
  Out-File "$env:USERPROFILE\Desktop\pliki_2126-07-21.txt" -Encoding UTF8