# Archiwum diagnostyczne Veeam / VMware — 27.10.2026

**Tryb: READ-ONLY wobec infrastruktury.** Skrypty moga utworzyc NOWE raporty lokalne na dysku systemowym. Nie zmieniaja zadan, backupow, repozytoriow ani konfiguracji vCenter. Zapytania metadanych nadal moga obciazyc serwer i baze Veeam — wybieraj okno z malym obciazeniem, nie uruchamiaj ich rownolegle.

## Srodowisko i zakres

- Serwer wykonawczy: `WINSERV19-VEEAM`, Windows PowerShell **5.1 x64**.
- Modul: `Veeam.Backup.PowerShell` **12.3.2.3617** (wersja potwierdzona 27.10.2026).
- vCenter zarejestrowane w Veeam: `horizon-vcenter.root.urk.edu.pl` oraz `10.43.1.10`.
- Nie wymaga VMware PowerCLI, instalacji ani zmian ExecutionPolicy.
- Skrypty w sekcjach `01`, `02`, `03` nie czytaja danych plikow VBK/VIB/VBM.
- **Wyjatek**: `04_Archiwum_Poczta/01_Generate_SHA256_Poczta_ORIGINAL.ps1` czyta CALE pliki backupow w celu obliczenia SHA256 (moze trwac dni, generuje I/O), ale ich nie zapisuje. Nie uruchamiac bez osobnej zgody.

## Jak czytac nazwy plikow

0. `00_Check_Script_Syntax_OFFLINE.ps1` — **pierwszy krok**: lokalna kontrola skladni wszystkich skryptow, niczego nie uruchamia.
1. `01_Inwentaryzacja/00_Preflight_READONLY.ps1` — lokalne sprawdzenie cmdletow.
2. `01_Inwentaryzacja/01_Export_vCenter_ViaVeeam_READONLY.ps1` — eksport JEDNEGO vCenter na uruchomienie (kopia poprawionej wersji narzedzia uzytego w audycie; nie jest to niezalezny od Veeam odczyt vCenter).
3. `01_Inwentaryzacja/02_Export_Veeam_21_Jobs_READONLY.ps1` — DOSLOWNA kopia pliku juz uzytego i zatwierdzonego dla 21 zadan Backup; warunek liczby zadan chroni przed przypadkowym uzyciem w zmienionym srodowisku.
4. `02_Katalog_i_punkty/03_Export_Veeam_Backup_Catalog_READONLY.ps1` — JEDEN odczyt katalogu backupow, bez restore pointow; moze zwrocic jedynie kontenery rodzicielskie backupow per-VM.
5. `02_Katalog_i_punkty/04_PILOT_One_VM_RestorePoints_READONLY.ps1` — punktowy test metadanych JEDNEJ VM w JEDNYM backupie. **NOWY, NIEZWERYFIKOWANY na tym konkretnym srodowisku; najpierw przeglad kodu i pilot.**
6. `03_Dyski_i_kontrola/05_PILOT_DiskFilter_FileServer_READONLY.ps1` — punktowe rozpoznanie wlasciwosci filtrow dyskow dla `WinServ2019-FileServer`; NIE interpretuje samodzielnie zakresu VMDK; potwierdzic w GUI Veeam. **NOWY, NIEZWERYFIKOWANY na serwerze**.
7. `03_Dyski_i_kontrola/06_Audit_Offline_CSV_Hashes.ps1` — analiza CSV lokalnie, bez polaczenia z Veeam.
8. `04_Archiwum_Poczta` — DWIE kopie istniejacych skryptow SHA256 z poprzedniego pakietu; odrebny projekt archiwizacji LTO-7, nie nalezy ich mylic z audytem metadanych VM.

## Przykladowe uruchomienia — dopiero po przegladzie kodu

```powershell
# Nie potrzeba dotykania repozytorium:
.\00_Preflight_READONLY.ps1

# Jeden vCenter na przebieg:
.\01_Export_vCenter_ViaVeeam_READONLY.ps1 -VCenterName '10.43.1.10'
.\01_Export_vCenter_ViaVeeam_READONLY.ps1 -VCenterName 'horizon-vcenter.root.urk.edu.pl'

# Katalog backupow: pierwszy nastepny etap po akceptacji:
.\03_Export_Veeam_Backup_Catalog_READONLY.ps1

# PILOT wybranej jednej VM - NIE wykonywac obu testow w ciemno:
.\04_PILOT_One_VM_RestorePoints_READONLY.ps1 -BackupName 'FileServer-URK' -VMName 'WinServ2019-FileServer'

# Tylko lokalnie, na plikach CSV:
.\06_Audit_Offline_CSV_Hashes.ps1 -CsvFolder 'C:\VeeamAudit\Exports\przykladowy_katalog' -OutputDir 'C:\VeeamAudit\Manifesty'
```

## Ograniczenia — jakich tez NIE wolno wyciagac

- `Include` nie oznacza ze kazdy dysk VMDK jest chroniony. Dla `WinServ2019-FileServer` rozne zadania moga chronic ROZNE dyski; 3 zadania = 1 VM, ale do 3 zakresow.
- `IsScheduleEnabled=True` nie dowodzi udanej ostatniej sesji.
- `Get-VBRBackup` moze zwrocic rodzicow i kontenery per-VM, nie kompletna liste per-VM.
- `Get-VBRRestorePoint -Backup -Name` pobiera metadane historycznych punktow; brak wyniku nie jest dowodem braku ochrony.
- Punkty na tasmach, backupy imported/orphaned, agent backup, inne infrastruktur/inne VBR wymagaja osobnego traktowania.
- `IsAvailable` i `IsConsistent`, nawet jesli sa dostepne, nie zastępuja testu odtwarzania.
- Nie uzywaj samej nazwy VM ani samego UUID do identyfikacji; glowny klucz vCenter: `HostId + ObjectRef` / `vCenter + Reference`. Duplikaty nazw i UUID wystepuja.
- Pomiary z vCenter sa widokiem inwentarza posredniczonym przez Veeam, a nie niezaleznym potwierdzeniem rzeczywistego stanu wszystkich vCenter.
- Dokumentacja online bywa dla Veeam 13: sprawdz `Get-Command ... -Syntax` w zainstalowanym 12.3 przed uruchomieniem nowych skryptow.

## Polityka uruchamiania i gromadzenia dowodow

1. Wymagane: uprawnienia read-only do API Veeam (o ile dostepne) i uzgodnione okno wykonania.
2. Sprawdz aktualny CPU/I/O i aktywne sesje Veeam. Nie uruchamiaj pelnej analizy restore pointow na raz.
3. Rozpocznij od jednego backupu i jednej VM; zachowaj wynik i zmierz czas wykonania.
4. Raporty sa poufne: zawieraja nazwy maszyn, hosty i wewnetrzne ID. Nie umieszczaj ich w publicznym repozytorium.
5. Zanotuj kto, kiedy, w jakiej wersji VBR, na jakim serwerze wykonal raport; zachowaj niezmodyfikowane CSV i SHA256.
6. Osobno sprawdz sesje zadan i zakres VMDK. Dla maszyn krytycznych zaplanuj testowe odtworzenie po zatwierdzeniu procedury.
7. Nie wykonuj zadnych komend Set-/Remove-/Start-/Stop-/Rescan- w ramach audytu.

## Odpowiedzialnosc i autorstwo

Ten pakiet stanowi robocza dokumentacje techniczna przygotowana do audytu. Przechowuj dowody autorstwa, historie zmian i sumy SHA-256. Prawa do utworow i materialow powstalych w ramach obowiazkow sluzbowych moga nalezec do pracodawcy lub podlegac umowie/regulaminom — nie zakladaj prywatnej wlasnosci bez ich sprawdzenia. Nie stosuj celowego ukrywania, blokowania ani utrudniania utrzymania systemow produkcyjnych.
