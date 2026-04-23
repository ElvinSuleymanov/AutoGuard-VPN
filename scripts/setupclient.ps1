#Requires -RunAsAdministrator

$ServerPublicIp = "PLACEHOLDER_SERVER_PUBLIC_IP"
$InterfaceName  = "PLACEHOLDER_INTERFACE_NAME"
$AuthKey        = "PLACEHOLDER_AUTH_KEY"

$WgExe = "C:\Program Files\WireGuard\wg.exe"
$WgGui = "C:\Program Files\WireGuard\wireguard.exe"

function CheckWireGuard {
    if (!(Test-Path $WgExe)) {
        Write-Host "WireGuard not found. Attempting install via winget..." -ForegroundColor Yellow
        try {
            winget install -e --id WireGuard.WireGuard --silent --accept-package-agreements --accept-source-agreements
            if (!(Test-Path $WgExe)) { throw }
        } catch {
            Write-Host "Auto-install failed. Download from https://www.wireguard.com/install/ then re-run." -ForegroundColor Red
            exit 1
        }
    }
}

function GenerateKeypair {
    $priv = & $WgExe genkey
    $pub  = $priv | & $WgExe pubkey
    return @{ Private = $priv; Public = $pub }
}

function RegisterPeer($PublicKey) {
    $body    = @{ public_key = $PublicKey } | ConvertTo-Json -Compress
    $headers = @{ "X-Auth-Token" = $AuthKey; "Content-Type" = "application/json" }
    $uri     = "https://$ServerPublicIp/addnewpeer"

    try {
        return Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -SkipCertificateCheck
    } catch [System.Management.Automation.ParameterBindingException] {
        Add-Type -TypeDefinition @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class _TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int e) { return true; }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object _TrustAll
        return Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body
    } catch {
        Write-Host "Registration failed: $_" -ForegroundColor Red
        exit 1
    }
}

function WriteConfig($Config, $PrivateKey) {
    $configDir  = "C:\ProgramData\WireGuard"
    $configPath = "$configDir\$InterfaceName.conf"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $Config = $Config -replace "<PASTE_YOUR_PRIVATE_KEY_HERE>", $PrivateKey
    Set-Content -Path $configPath -Value $Config -Encoding UTF8
    icacls $configPath /inheritance:r /grant:r "SYSTEM:(F)" /grant:r "Administrators:(F)" | Out-Null
    return $configPath
}

function InstallTunnel($ConfigPath) {
    & $WgGui /installtunnelservice $ConfigPath
    Start-Sleep -Seconds 3
    try { Start-Service -Name "WireGuardTunnel`$$InterfaceName" -ErrorAction Stop }
    catch { Write-Host "Service start failed — check WireGuard logs." -ForegroundColor Yellow }
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   AUTOGUARD VPN CLIENT SETUP                   " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

CheckWireGuard

Write-Host "`n🔑 Generating WireGuard keypair..." -ForegroundColor Cyan
$Keys = GenerateKeypair
Write-Host "✅ Keypair generated." -ForegroundColor Green

Write-Host "📡 Registering with VPN server at $ServerPublicIp..." -ForegroundColor Cyan
$Response = RegisterPeer -PublicKey $Keys.Public
if ($Response.status -ne "ok") {
    Write-Host "Registration failed: $($Response | ConvertTo-Json)" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Registered. Assigned IP: $($Response.ip)" -ForegroundColor Green

$ConfigPath = WriteConfig -Config $Response.config -PrivateKey $Keys.Private
Write-Host "✅ Config written to $ConfigPath" -ForegroundColor Green

Write-Host "🚀 Installing WireGuard tunnel service..." -ForegroundColor Cyan
InstallTunnel -ConfigPath $ConfigPath
Write-Host "✅ VPN is active on interface $InterfaceName." -ForegroundColor Green
