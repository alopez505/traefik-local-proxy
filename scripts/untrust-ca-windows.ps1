# Remove the Traefik Local Proxy dev CA from the Windows CurrentUser trust store.
# No administrator privileges required.
#
# Run from WSL2 via:
#   mise run untrust-ca
# Or directly:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/untrust-ca-windows.ps1

$subject = "*Traefik Local Proxy Dev CA*"
$removed = 0

Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Subject -like $subject } |
    ForEach-Object {
        Remove-Item $_.PSPath
        Write-Host "Removed: $($_.Subject)"
        $removed++
    }

if ($removed -eq 0) {
    Write-Host "No Traefik Local Proxy Dev CA found in CurrentUser\Root."
} else {
    Write-Host "$removed certificate(s) removed."
}
