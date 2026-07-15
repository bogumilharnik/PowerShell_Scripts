## Summary

Wyeksportowanie pelnej konfiguracji systemu Veeam Backup & Replication do pliku TXT - jako dokumentacja stanu faktycznego.

Obejmuje:
        - naglowek (data, serwer, uzytkownik, wersja Veeam),
        - GLOBALNE ustawienia powiadomien e-mail (SMTP, From, To, Subject, Notify on Success/Warning/Failure),
        - WSZYSTKIE zadania backup'owe (VM / Agent / Tasmowe) wraz z                      ustawieniami powiadomien kazdego zadania,
        - repozytoria backup'owe.

## How to run script

    Uruchomienie (na serwerze Veeam B&R, PowerShell "jako administrator"):

        powershell -ExecutionPolicy Bypass -File .\Export-VeeamConfig.ps1

        Opcjonalnie mozna wskazac wlasna sciezke pliku wyjsciowego:
        powershell -ExecutionPolicy Bypass -File .\Export-VeeamConfig.ps1 -OutputFile "C:\Dowody\veeam.txt"

## Recomendations & Warnings && Dependencies

    Uwaga: zalecane uruchomienie w Windows PowerShell 5.1 (modul Veeam dziala tam najstabilniej). Skrypt jest tylko do ODCZYTU - nie zmienia  zadnych ustawien systemu.