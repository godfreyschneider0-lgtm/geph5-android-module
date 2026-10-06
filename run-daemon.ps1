# Elevated launcher for the geph5 manager (Phase A verification).
# Runs the manager with the uninstalled engine build and tees logs to a file.
$ErrorActionPreference = 'Continue'
$env:GEPH_CLIENT_BIN = 'Z:\geph5\target\debug\geph5-client.exe'
$env:RUST_LOG = 'geph=info,warn'
Set-Location 'Z:\geph5\target\debug'
& 'Z:\geph5\target\debug\geph5.exe' manager *>&1 |
    Tee-Object -FilePath 'Z:\geph5\manager.log'
