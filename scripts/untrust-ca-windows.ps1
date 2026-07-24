# Remove the mkcert development CA from the Windows CurrentUser trust store.
# No administrator privileges required.
#
# Note: by default, mkcert uses one CA per user profile, shared by all projects
# using the same CAROOT. Removing it from this user's trust store may therefore
# affect other mkcert-based projects for this Windows user.
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
