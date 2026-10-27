#requires -Version 5.1
<#
.SYNOPSIS
  Weryfikacja SKLADNI wszystkich plikow .ps1 w folderze pakietu.
.DESCRIPTION
  NIE wykonuje zadnych skryptow. Parser systemowy odczytuje pliki lokalnie.
  Uruchomic w Windows PowerShell 5.1 z katalogu rozpakowanego pakietu.
#>
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$files=@(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse)
if($files.Count -eq 0){throw 'Brak plikow do weryfikacji.'}
$errCount=0
foreach($file in $files){
  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $file.FullName,[ref]$tokens,[ref]$errors
  )
  if($errors.Count -gt 0){
    foreach($error in $errors){
      Write-Warning ("{0}:{1}: {2}" -f $file.Name,$error.Extent.StartLineNumber,$error.Message)
      $errCount++
    }
  } else {
    Write-Host ("OK - {0}" -f $file.FullName)
  }
}
Write-Host ("Pliki: {0}; bledy skladni: {1}" -f $files.Count,$errCount)
if($errCount -gt 0){throw 'WYKRYTO BLEDY SKLADNI - nie uruchamiaj tych skryptow.'}
