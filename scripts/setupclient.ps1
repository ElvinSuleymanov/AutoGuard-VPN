
if ((Get-Command wireguard -ErrorAction SilentlyContinue) -or (Get-Command wg -ErrorAction SilentlyContinue)) {
    Write-Output "WireGuard CLI is accessible."
} else {
    Write-Output "Binary not found in PATH."
}