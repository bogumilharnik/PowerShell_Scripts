Date format: YYYY-MM-DD

forfiles /P F:\RepositoryISCSI /S /D 2126-07-21 /C "cmd /c echo @path @fdate" | findstr "2126-07-21"

Date format: DD.MM.YYYY

forfiles /P F:\RepositoryISCSI /S /D +21.07.2126 /C "cmd /c echo @path @fdate" | findstr "21.07.2126"

Date format: MM-DD-YYYY

forfiles /P F:\RepositoryISCSI /S /D +07-21-2126 /C "cmd /c echo @path @fdate" | findstr "07-21-2126"