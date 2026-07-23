Date format: YYYY-MM-DD

forfiles /P F:\RepositoryISCSI /S /D 2026-07-21 /C "cmd /c echo @path @fdate" | findstr "2026-07-21"

Date format: DD.MM.YYYY

forfiles /P F:\RepositoryISCSI /S /D +22.07.2026 /C "cmd /c echo @path @fdate" | findstr "22.07.2026"

Date format: MM-DD-YYYY

forfiles /P F:\RepositoryISCSI /S /D +07-21-2026 /C "cmd /c echo @path @fdate" | findstr "07-21-2026"