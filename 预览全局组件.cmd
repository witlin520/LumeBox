@echo off
cd /d "%~dp0"
call C:\flutter\bin\flutter.bat run -d windows -t tool/theme_components_preview.dart
pause
