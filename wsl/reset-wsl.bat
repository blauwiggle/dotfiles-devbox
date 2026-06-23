@echo off
REM ============================================================
REM  reset-wsl.bat  -  WSL-Netzwerk auf sicheren Stand zuruecksetzen
REM  Ausfuehren in WINDOWS (Doppelklick oder Rechtsklick > Ausfuehren),
REM  NICHT in der WSL-Shell. Hilft, falls WSL nach einer Netz-Aenderung
REM  (z.B. networkingMode=mirrored) kein Netzwerk mehr hat.
REM  Wichtig: Die Dev Box selbst ist NIE betroffen - RDP geht zu Windows.
REM ============================================================
echo.
echo Setze %USERPROFILE%\.wslconfig auf sicheren NAT-Standard zurueck...
(
echo [wsl2]
echo dnsTunneling=true
echo autoProxy=true
echo processors=6
)> "%USERPROFILE%\.wslconfig"

echo Fahre WSL herunter...
wsl --shutdown

echo.
echo Fertig. WSL nutzt wieder den sicheren NAT-Standard.
echo Oeffne WSL neu (Windows App / Terminal).
echo.
pause
