@echo off
cls
set PGPASSWORD=DaVinci
set PG_EXE_PATH=D:\Users\praveen\postgresql-13.4-1-windows-x64.exe
CALL :GetPGSQLOldVersion PG_PATH_OLD
CALL :ReIndexOldPostgreSQL "%PG_PATH_OLD%"

CALL :InstallingPostgreSQL "%PG_EXE_PATH%" PG_PATH_NEW %PGPASSWORD%
CALL ::MigrateData "%PG_PATH_OLD%" "%PG_PATH_NEW%"
EXIT /B %ERRORLEVEL%

:GetPGSQLOldVersion
	if EXIST "%ProgramFiles%\PostgreSQL\9.5\bin" (
		set %~1=%ProgramFiles%\PostgreSQL\9.5
		EXIT /B 0
	)
	if EXIST "%ProgramFiles%\PostgreSQL\9.2\bin" (
		set %~1=%ProgramFiles%\PostgreSQL\9.2
		EXIT /B 0
	)
	if EXIST "%ProgramFiles%\PostgreSQL\9.0\bin" (
		set %~1=%ProgramFiles%\PostgreSQL\9.0
		EXIT /B 0
	)
EXIT /B 0

:ReIndexOldPostgreSQL
	if EXIST "%~1\bin" (
		if NOT EXIST "%~1\data\postmaster.pid" (
			echo STARTING OLD
			"%~1\bin\pg_ctl.exe" -D "%~1\data" start
		)
		echo "ReIndexOldPostgreSQL %~1"
		"%~1\bin\reindexdb.exe" --all --username postgres
		"%~1\bin\pg_ctl.exe" -D "%~1\data" stop -m fast
		echo stopped server %~1
	)
EXIT /B 0

:StopRunningPostgreSQL
	if EXIST "%~1\data\postmaster.pid" (
		"%~1\bin\pg_ctl.exe" -D "%~1\data" stop -m fast
		echo "stopped ... %~1"
	)
EXIT /B 0

:InstallingPostgreSQL
	if EXIST "%~1" (
		echo "%~1 --mode unattended --superpassword %~3"
		"%~1" --mode unattended --superpassword %~3
		set %~2=%ProgramFiles%\PostgreSQL\13
	)
EXIT /B 0

:MigrateData
	if EXIST %~1\bin (
		CALL :StopRunningPostgreSQL "%~1"
		CALL :StopRunningPostgreSQL "%~2"
		
		CALL :GetMethod "%~1" OLD_METHOD
		CALL :GetMethod "%~2" NEW_METHOD
		
		set HBA_CONF=%~2\data\pg_hba.conf
		set HBA_CONF_BAK=pg_hba_bak.conf
		mv "%HBA_CONF%" "%HBA_CONF_BAK%"
		
		echo local   all             all                                     trust > "%HBA_CONF%"
		echo host    all             all             127.0.0.1/32            trust >> "%HBA_CONF%"
		echo host    all             all             ::1/128                 trust >>  "%HBA_CONF%"
		
		"%~2\bin\pg_upgrade.exe" -U postgres -d "%~1\data" -D "%~2\data" -b "%~1\bin" -B "%~2\bin"
		
		"%~2\bin\pg_ctl.exe" -D "%~2\data" start"
		"%~2\bin\psql.exe" --host 127.0.0.1 --username postgres -c "ALTER USER postgres WITH PASSWORD '%PGPASSWORD%'"
		
		if EXIST "reindex_hash.sql" (
			"%~2\bin\psql.exe" --host 127.0.0.1 --username postgres < reindex_hash.sql
		)
		
		:: Merging pg_hba.conf file
		CALL :UpdatePGHBAFile "%~1" "%~2" %OLD_METHOD% %NEW_METHOD% %HBA_CONF_BAK%
		"%~2\bin\pg_ctl.exe" -D "%~2\data" restart"
	)
EXIT /B 0

:GetMethod
	if EXIST "%~1\data\pg_hba.conf" (
		for /f "tokens=4* usebackq" %%a in (`type "%~1\data\pg_hba.conf" ^| findstr "::1" ^| findstr -v "replication #"`) do (
			set %~2=%%b
		)
	)
EXIT /B 0

:UpdatePGHBAFile
	setlocal
	set HBA_CONF_OLD=%~1\data\pg_hba.conf
	set HBA_CONF_NEW=%~2\data\pg_hba.conf
	if EXIST "%~5" (
		DEL "%HBA_CONF_NEW%"
	)
	
	if EXIST %HBA_CONF_OLD% (
		for /f "tokens=* usebackq" %%a in (`type "%HBA_CONF_OLD%" ^| findstr -v "::1 local 127.0.0.1 #"`) do (
			setlocal enabledelayedexpansion
			set "string=%%a"
			echo !string:%~3=%~4! >> "%HBA_CONF_NEW%"
			endlocal			
		)
	)
	
	for /f "tokens=* usebackq" %%a in (`type "%~5" ^| findstr -v "#"`) do (
			setlocal enabledelayedexpansion
			set "string=%%a"
			echo !string! >> "%HBA_CONF_NEW%"
			endlocal			
		)
	endlocal
EXIT /B 0
