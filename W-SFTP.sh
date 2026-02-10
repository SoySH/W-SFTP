@echo off
chcp 65001 >nul
title Instalador SFTP - OpenSSH para Windows
setlocal enabledelayedexpansion

:: Función para pausar
:pause
echo.
pause
goto menu

:menu
cls
echo ========================================
echo         INSTALADOR SFTP WINDOWS
echo ========================================
echo 1. Instalar servidor SFTP (OpenSSH)
echo 2. Desinstalar servidor SFTP
echo 3. Salir
echo ========================================
set /p option=Selecciona una opción [1-3]: 

if "%option%"=="1" goto instalar
if "%option%"=="2" goto desinstalar
if "%option%"=="3" exit
goto menu

:instalar
cls
echo --- Instalación del servidor SFTP ---

:: Solicitar usuario, contraseña y puerto
set /p sftp_user=Introduce el nombre del usuario SFTP: 
set /p sftp_pass=Introduce la contraseña del usuario: 
set /p sftp_port=Introduce el puerto a utilizar [por defecto 22]: 

if "%sftp_port%"=="" set sftp_port=22

:: Validar contraseña (mínimo 8 caracteres)
set len=0
for /f %%A in ('powershell "[int](\"%sftp_pass%\".Length)"') do set len=%%A
if %len% LSS 8 (
    echo ❌ La contraseña debe tener al menos 8 caracteres.
    goto pause
)

set "sftp_root=C:\SFTP"
set "user_folder=%sftp_root%\%sftp_user%"

:: Crear carpeta principal
mkdir "%user_folder%" >nul 2>&1

:: Crear o actualizar usuario
powershell -Command "if (Get-LocalUser -Name '%sftp_user%' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if %errorlevel%==0 (
    echo ⚠️  El usuario ya existe. Actualizando la contraseña...
    powershell -Command "$u='%sftp_user%'; $p=ConvertTo-SecureString '%sftp_pass%' -AsPlainText -Force; Set-LocalUser -Name $u -Password $p"
) else (
    echo ➕ Creando nuevo usuario...
    powershell -Command "$p=ConvertTo-SecureString '%sftp_pass%' -AsPlainText -Force; New-LocalUser -Name '%sftp_user%' -Password $p -FullName 'Usuario SFTP' -Description 'Cuenta para acceso SFTP'"
)

:: Añadir usuario al grupo Users (por si acaso)
powershell -Command "Add-LocalGroupMember -Group 'Users' -Member '%sftp_user%'" >nul 2>&1

:: Instalar OpenSSH
echo Instalando OpenSSH Server...
powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"

:: Iniciar y configurar el servicio
powershell -Command "Start-Service sshd"
powershell -Command "Set-Service -Name sshd -StartupType Automatic"

:: Permisos carpeta
cmd /c icacls "%user_folder%" /grant "%sftp_user%":(OI)(CI)M /T
cmd /c icacls "%user_folder%" /setowner "%sftp_user%" /T

:: Crear configuración sshd_config
set "sshd_cfg=%ProgramData%\ssh\sshd_config"
echo Subsystem sftp internal-sftp> "%sshd_cfg%"
echo Port %sftp_port%>> "%sshd_cfg%"
echo Match User %sftp_user%>> "%sshd_cfg%"
echo ^    ChrootDirectory %user_folder%>> "%sshd_cfg%"
echo ^    ForceCommand internal-sftp>> "%sshd_cfg%"
echo ^    AllowTcpForwarding no>> "%sshd_cfg%"
echo ^    X11Forwarding no>> "%sshd_cfg%"

:: Reiniciar servicio para aplicar cambios
powershell -Command "Restart-Service sshd"

:: Firewall
powershell -Command "New-NetFirewallRule -Name 'OpenSSH_SFTP' -DisplayName 'OpenSSH SFTP' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort %sftp_port%" >nul 2>&1

echo.
echo ✅ Instalación completada.
echo 📁 Ruta del usuario: %user_folder%
echo 🔐 Usuario: %sftp_user%
echo 📡 Puerto SFTP: %sftp_port%
goto pause

:desinstalar
cls
echo --- DESINSTALACIÓN del servidor SFTP ---
set /p conf=¿Estás seguro que deseas eliminar todo? [S/N]: 
if /I "%conf%" NEQ "S" goto menu

set /p user_del=Nombre del usuario a eliminar: 

:: Detener y desinstalar OpenSSH
powershell -Command "Stop-Service sshd -ErrorAction SilentlyContinue"
powershell -Command "Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"

:: Eliminar firewall
powershell -Command "Remove-NetFirewallRule -Name 'OpenSSH_SFTP' -ErrorAction SilentlyContinue"

:: Eliminar carpetas
rmdir /s /q "C:\SFTP" >nul 2>&1
takeown /f "C:\ProgramData\ssh" /r /d y >nul 2>&1
icacls "C:\ProgramData\ssh" /grant administrators:F /t >nul 2>&1
rmdir /s /q "C:\ProgramData\ssh" >nul 2>&1

:: Eliminar usuario
powershell -Command "Remove-LocalUser -Name '%user_del%' -ErrorAction SilentlyContinue"

echo 🧹 Desinstalación completa.
goto pause
