# Plan audytu dwupoziomowego i wymogi dowodowe

## Jednostki ewidencji

- **VM**: unikalny klucz infrastruktury `(vCenter HostId, VMware MoRef)`, dodatkowo nazwa, UUID, folder, host.
- **Przypisanie do zadania**: `(JobId, SourceHostId, SourceObjectRef, EntryType)`; osobny rekord dla kazdego zadania. Potencjalne wylaczenia dyskow na poziomie VM wymagaja dodatkowego rejestru.
- **Zakres VMDK**: `(VM key, JobId, DiskKey / kontroler / sciezka, Include/Exclude)` — ten wymiar NIE zostal jeszcze wyeksportowany; bez niego stan "PELNA OCHRONA" jest niedopuszczalny.
- **Restore point**: `(BackupId, PointId, VM identification, timestamp, type, available/consistent, chain/repository)` — po odczycie metadanych i identyfikacji ograniczen API.
- **Task session**: `(SessionId, JobId, VM, data, Result, Status)` — pomiar skutecznosci przetwarzania maszyny.

## Dowody dla pozytywnego statusu

A. Wpis w konfiguracji: tylko "wskazano w zadaniu".
B. Punkt przywracania: "zarejestrowany"; odnotowac date, wiek i backup chain.
C. Sesja: po sprawdzeniu wyniku sesji i zadan VM mozna stwierdzic "ostatnia operacja zakonczyla sie ...".
D. Integralnosc: po weryfikacji zdrowia lancucha / validator / health-check (zalezy od metody).
E. Odtwarzalnosc: wykonany, udokumentowany test odtworzenia, pomiar RTO/RPO i spojnosc aplikacyjna.

## Obowiazkowe rozroznienia

- Trzy zadania dla `WinServ2019-FileServer` (FileServer-URK, FileServer-URK_WL, FileServer-URK_WHIBZ) to 1 VM i kilka zakresow ochrony, NIE 3 VM.
- Backup uslugi Poczta i Poczta-NEW: nie utozsamiac aktywnosci/historii bez zgodnego identyfikatora VM i backupu.
- Kontener Resource Pool Horizon: dopasowanie `HostId + resgroup-14674` potwierdza IDENTYCZNOSC puli, lecz nie lista wszystkich aktualnych czlonkow i wykluczen.
- Jeden lub wiele backupow moze byc wylacznie historycznych/importowanych; odrebna klasyfikacja.
- Wykluczenie calej maszyny != wykluczenie dysku.
- Wyrazenie "NIECHRONIONA" wymaga potwierdzenia braku ochrony w badanym zakresie wszystkich ustalonych systemow / metod; inaczej "BRAK POTWIERDZENIA".

## Nie mozemy zapewnic "absolutnej pewnosci"

Audyt to dowody w okreslonym momencie. Dla krytycznych VM trzeba ustalic wymagania biznesowe RPO/RTO, backup aplikacyjny, zakres VMDK, offsite/immutable, retencje, bledy sesji, dostepnosc lancucha i testowe odtworzenie. Sam katalog VBR nie wystarcza.

## Co dalej po pilocie

1. Kontrola wyniku i czasu `03_Export_Veeam_Backup_Catalog_READONLY.ps1`.
2. Pilot `04_PILOT_One_VM_RestorePoints_READONLY.ps1` dla JEDNEJ VM. Potwierdzenie nazwy i identyfikatorow COib w VBR 12.3.2.3617.
3. Planowany osobny, etapowany eksport po BackupId/VM, bez nieograniczonego globalnego Get-VBRRestorePoint.
4. Eksport ostatnich sesji zadan i zadan VM, ale dopiero po weryfikacji cmdletow i schematu zwracanych obiektow.
5. Potwierdzenie filtracji dyskow w GUI Veeam i ewentualnie jawny zapis konfiguracji w raporcie.
6. Raport macierzowy wraz z przypadkami "BRAK POTWIERDZENIA" i polem na akceptacje wyjatkow.
