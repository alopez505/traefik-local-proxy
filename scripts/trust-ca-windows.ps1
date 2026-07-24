# Import the mkcert development CA (certs/ca.crt) into the Windows CurrentUser
# trust store. No administrator privileges required - CurrentUser\Root is
# user-scoped.
#
# Run from WSL2 via:
#   mise run trust-ca
# Or directly:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/trust-ca-windows.ps1

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$certPath  = Join-Path $scriptDir "..\certs\ca.crt"
$certPath  = [System.IO.Path]::GetFullPath($certPath)

if (-not (Test-Path $certPath)) {
    Write-Error "CA certificate not found at: $certPath"
    Write-Error "Run 'mise run certs' first to generate it."
    exit 1
}

Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certPath
$trustedCertificate = Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
    Select-Object -First 1

if ($null -eq $trustedCertificate) {
    Write-Error "The CA import completed without an error, but its thumbprint was not found in CurrentUser\Root."
    exit 1
}

Write-Output "Imported: $certPath"
Write-Output "CA is now trusted in CurrentUser\Root."
Write-Output "To remove it later, run: mise run untrust-ca"
