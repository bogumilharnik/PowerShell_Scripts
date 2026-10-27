#requires -Version 5.1
<#
.SYNOPSIS
  Wstepny odczyt wlasciwosci filtracji dyskow dla trzech wpisow VM FileServer.
.DESCRIPTION
  Tylko Get-VBRJob i Get-VBRJobObject dla wskazanych zadan. NIE wywolywac
  metod typu Set/Update. Wyswietla typy .NET i nazwane skalarne wlasciwosci
  DiskFilter/DiskFilterInfo. Nie dowodzi zakresu VMDK bez weryfikacji w GUI.
  Nie zapisuje nic na dysku.
#>
$ErrorActionPreference='Stop'
$names=@('FileServer-URK','FileServer-URK_WL','FileServer-URK_WHIBZ')
$cmd=Get-Command Get-VBRJobObject -ErrorAction Stop
if($cmd.Source -ne 'Veeam.Backup.PowerShell'){throw 'Nieoczekiwane zrodlo Get-VBRJobObject'}
$allJobs=@(Get-VBRJob -ErrorAction Stop)
foreach($name in $names) {
    $jobs=@($allJobs | Where-Object {$_.Name -eq $name -and [string]$_.JobType -eq 'Backup'})
    if($jobs.Count -ne 1) {Write-Warning "Nie znaleziono jednoznacznie zadania $name";continue}
    $items=@(Get-VBRJobObject -Job $jobs[0] -ErrorAction Stop |
             Where-Object { $_.Name -eq 'WinServ2019-FileServer' -and $_.IsIncluded })
    Write-Host "`nJOB: $name, wiersze Include: $($items.Count)"
    foreach($item in $items) {
        [PSCustomObject]@{Job=$name;VM=$item.Name;SourceRef=[string]$item.Object.ObjectRef;
          HostId=[string]$item.Object.HostId;IsExcludeDisksChild=$item.IsExcludeDisksChild} | Format-List
        foreach($propName in @('DiskFilter','DiskFilterInfo')) {
            $prop=$item.PSObject.Properties[$propName]
            if($null -eq $prop) { Write-Host "Brak wlasciwosci: $propName";continue }
            $value=$prop.Value
            if($null -eq $value){Write-Host "$propName = null";continue}
            Write-Host "$propName type: $($value.GetType().FullName)"
            # Nie serializujemy zlozonych obiektow .NET (moglyby miec kosztowne gettery).
            Write-Host 'Nazwy wlasciwosci obiektu:'
            $value | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            if($value -is [string] -or $value.GetType().IsPrimitive) {
                Write-Host "$propName (wartosc prosta): $value"
            }
        }
    }
}
Write-Warning 'Ten test nie potwierdza listy chronionych VMDK. Zweryfikuj ustawienia DISKS w GUI dla kazdego zadania.'
