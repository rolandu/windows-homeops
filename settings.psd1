@{
    # Chocolatey packages to install/ensure (IDs must be exact)
    Packages = @(
        '7zip'              # File archiver
        'cyberduck'         # GUI FTP/SFTP/WebDAV client
        'firefox'           # Web browser
        'git'               # Git VCS
        'libreoffice-still' # LibreOffice stable branch (slower updates)
        'notepadplusplus'   # Notepad replacement
        'powershell-core'   # PowerShell 7 (pwsh)
        'rclone'            # Cloud storage sync/CLI
        'syncthing'         # Peer-to-peer file sync engine
        'synctrayzor'       # Windows tray host for Syncthing
        'thunderbird'       # Email client
        'vim'               # Vim editor
        'vlc'               # Media player
        'windirstat'        # Disk usage analyzer
        'winfsp'            # Windows FUSE (filesystem) support
    )

    # Winget packages to install/ensure (IDs must be exact)
    WingetPackages = @(
        'RustDesk.RustDesk' # Remote desktop tool (self-hostable)
    )
}
