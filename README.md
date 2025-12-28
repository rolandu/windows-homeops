# Windows Homeops

This represents my default Windows 11 base setup.

## Windows Setup

1. If the machine did not come with it, install Windows from Install Medium - https://www.microsoft.com/en-us/software-download/windows11
2. If the machine did not come with it, buy a license
3. run `.\bootstrap.ps1` in a Powershell Terminal (with admin rights) for base setup
4. Manual Install for packages without scriptable installer:
    - Password Manager: Bitwarden: the choco package only installs per single-user; instead install manually and select "install for all users": https://bitwarden.com/download/
    - Backup: Veeam Agent Windows Free: install manually: https://www.veeam.com/products/free/microsoft-windows.html

## Bootstrap.ps1

- Run as administrator
- Installs applications (mostly using chocolateley) using package lists from `settings.psd1`
- Performs upgrades
- Sets some defaults in Windows (including a security/privacy baseline)
- Idempotent (can run again and again without impact)
- If script execution is disabled, start a session with `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` then run `.\bootstrap.ps1`.

## Optional steps

- install more tools; e.g.
    - scoop
    - steam
    - games
    - vscode

