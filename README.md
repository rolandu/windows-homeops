# Windows Homeops

This represents my default Windows 11 base setup and preferences. I publish it mainly so I have it available on machines whenever I need it. Feel free to use this repository as a template for your own setup.

Works on Windows 11 Home as well as Pro.

## Windows Setup

1. If the machine did not come with it, install Windows from Install Medium - https://www.microsoft.com/en-us/software-download/windows11
2. If the machine did not come with it, buy a Windows license
3. run `.\bootstrap.ps1` in a Powershell Terminal (with admin rights) for base setup
    - If script execution is disabled, start a session with `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` then run `.\bootstrap.ps1`.
4. Manual Install for packages without scriptable installer:
    - Password Manager: **Bitwarden**: the choco package only installs per single-user; instead install manually and select "install for all users": https://bitwarden.com/download/
    - Backup: **Veeam Agent** Windows Free: install manually: https://www.veeam.com/products/free/microsoft-windows.html

## Bootstrap.ps1

- Run as administrator
- Installs applications using package lists from `settings.psd1`
- Performs available upgrades
- Sets some defaults in Windows (including a security/privacy baseline)
- Can disable selected startup apps (Task Manager “Startup apps”) configured via `StartupDisableNames` in `settings.psd1` (e.g., RustDesk)
- Idempotent (can run again and again without impact)

For installing / upgrading we use first the **chocolateley** package manager (preferred) and then **winget** package manager (for other packages).

### Important notice

Running `bootstrap.ps1` will automatically accept source/package terms and install/upgrade the listed software without additional prompts. By running it you confirm you have reviewed and agree to the relevant licenses/terms for every source and package and accept the risks of automated installation.

## Optional steps

- install more tools; e.g.
    - scoop
    - steam
    - games
    - vscode
