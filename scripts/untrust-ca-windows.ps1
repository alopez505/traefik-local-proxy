# Remove the mkcert development CA from the Windows CurrentUser trust store.
# No administrator privileges required.
#
# Note: by default, mkcert uses one CA per user profile, shared by all projects
# using the same CAROOT. This script removes only the CA matching certs/ca.crt,
# but projects that share that CA will also stop trusting it.
#
# Run from WSL2 via:
#   mise run untrust-ca
# Or directly:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/untrust-ca-windows.ps1

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$certPath  = Join-Path $scriptDir "..\certs\ca.crt"
$certPath  = [System.IO.Path]::GetFullPath($certPath)

if (-not (Test-Path $certPath)) {
    Write-Error "CA certificate not found at: $certPath"
    Write-Error "The exact trusted certificate cannot be identified without certs/ca.crt."
    exit 1
}

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certPath
$trustedCertificate = Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
    Select-Object -First 1

if ($null -eq $trustedCertificate) {
    Write-Output "CA is not present in CurrentUser\Root: $($certificate.Thumbprint)"
} else {
    Remove-Item $trustedCertificate.PSPath

    $remainingCertificate = Get-ChildItem Cert:\CurrentUser\Root |
        Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
        Select-Object -First 1

    if ($null -ne $remainingCertificate) {
        Write-Error "The CA is still present in CurrentUser\Root after removal."
        exit 1
    }

    Write-Output "Removed: $($trustedCertificate.Subject)"
    Write-Output "Thumbprint: $($trustedCertificate.Thumbprint)"
}
