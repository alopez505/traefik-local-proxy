# Import the mkcert development CA (certs/ca.crt) into the Windows CurrentUser
# trust store. No administrator privileges required - CurrentUser\Root is
# user-scoped.
#
# Run from WSL2 via:
#   mise run trust-ca
# Or directly:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/trust-ca-windows.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$certPath  = Join-Path $scriptDir "..\certs\ca.crt"
$certPath  = [System.IO.Path]::GetFullPath($certPath)

if (-not (Test-Path $certPath)) {
    Write-Error "CA certificate not found at: $certPath"
    Write-Error "Run 'mise run certs' first to generate it."
    exit 1
}

Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Write-Host "Imported: $certPath"
Write-Host "CA is now trusted in CurrentUser\Root."
Write-Host "To remove it later, run: mise run untrust-ca"
