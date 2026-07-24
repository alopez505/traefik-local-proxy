# Remove the mkcert development CA from the Windows CurrentUser trust store.
# No administrator privileges required.
#
# Note: mkcert uses a single machine-wide CA (in its CAROOT), so this removes
# the CA that any other mkcert-based project on this machine also relies on.
#
# Run from WSL2 via:
#   mise run untrust-ca
# Or directly:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/untrust-ca-windows.ps1

$subject = "*mkcert*"
$removed = 0

Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Subject -like $subject } |
    ForEach-Object {
        Remove-Item $_.PSPath
        Write-Host "Removed: $($_.Subject)"
        $removed++
    }

if ($removed -eq 0) {
    Write-Host "No mkcert CA found in CurrentUser\Root."
} else {
    Write-Host "$removed certificate(s) removed."
}
