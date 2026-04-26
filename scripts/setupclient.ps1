#Requires -RunAsAdministrator

$ServerPublicIp = "PLACEHOLDER_SERVER_PUBLIC_IP"
$InterfaceName  = "PLACEHOLDER_INTERFACE_NAME"
$AuthKey        = "PLACEHOLDER_AUTH_KEY"

$WgExe = "C:\Program Files\WireGuard\wg.exe"
$WgGui = "C:\Program Files\WireGuard\wireguard.exe"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

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

    $params = @{ Uri = $uri; Method = "POST"; Headers = $headers; Body = $body }
    if ($PSVersionTable.PSVersion.Major -ge 7) { $params["SkipCertificateCheck"] = $true }

    try {
        return Invoke-RestMethod @params
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
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($configPath, $Config, $utf8NoBom)
    icacls $configPath /inheritance:r /grant:r "SYSTEM:(F)" /grant:r "Administrators:(F)" | Out-Null
    return $configPath
}

function EnsureTunnelUp($ConfigPath) {
    if (!(Test-Path $ConfigPath)) {
        Write-Host "Config file not found at $ConfigPath — aborting." -ForegroundColor Red
        exit 1
    }

    $bytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "Stripping BOM from config..." -ForegroundColor Yellow
        [System.IO.File]::WriteAllBytes($ConfigPath, $bytes[3..($bytes.Length - 1)])
    }

    $svcName = "WireGuardTunnel`$$InterfaceName"
    $svc     = Get-Service -Name $svcName -ErrorAction SilentlyContinue

    if (-not $svc) {
        & $WgGui /installtunnelservice $ConfigPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Tunnel install failed (exit $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
    } elseif ($svc.Status -ne "Running") {
        try { Start-Service -Name $svcName -ErrorAction Stop }
        catch {
            Write-Host "Service won't start, reinstalling..." -ForegroundColor Yellow
            & $WgGui /uninstalltunnelservice $InterfaceName | Out-Null
            $deadline = (Get-Date).AddSeconds(15)
            while ((Get-Service -Name $svcName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 500
            }
            & $WgGui /installtunnelservice $ConfigPath
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Reinstall failed (exit $LASTEXITCODE)." -ForegroundColor Red
                exit 1
            }
        }
    }

    Start-Process $WgGui
}

function ReinstallTunnel($ConfigPath) {
    $svcName = "WireGuardTunnel`$$InterfaceName"
    if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
        & $WgGui /uninstalltunnelservice $InterfaceName | Out-Null
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Service -Name $svcName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
        }
    }
    EnsureTunnelUp -ConfigPath $ConfigPath
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   AUTOGUARD VPN CLIENT SETUP                   " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

CheckWireGuard

$configPath = "C:\ProgramData\WireGuard\$InterfaceName.conf"
$endpointPattern = "Endpoint\s*=\s*" + [regex]::Escape($ServerPublicIp) + "\s*:"

if (Test-Path $configPath) {
    $existing = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch $endpointPattern) {
        Write-Host "$InterfaceName.conf belongs to another VPN. Installing AutoGuard as 'autoguard' instead." -ForegroundColor Yellow
        $InterfaceName = "autoguard"
        $configPath    = "C:\ProgramData\WireGuard\$InterfaceName.conf"
    }
}

if (Test-Path $configPath) {
    Write-Host "AutoGuard config already exists. Bringing up existing tunnel..." -ForegroundColor Yellow
    EnsureTunnelUp -ConfigPath $configPath
    Write-Host "VPN is active on interface $InterfaceName." -ForegroundColor Green
    exit 0
}

Write-Host "`nGenerating WireGuard keypair..." -ForegroundColor Cyan
$Keys = GenerateKeypair
Write-Host "Keypair generated." -ForegroundColor Green

Write-Host "Registering with VPN server at $ServerPublicIp..." -ForegroundColor Cyan
$Response = RegisterPeer -PublicKey $Keys.Public
if ($Response.status -ne "ok") {
    Write-Host "Registration failed: $($Response | ConvertTo-Json)" -ForegroundColor Red
    exit 1
}
Write-Host "Registered. Assigned IP: $($Response.ip)" -ForegroundColor Green

$ConfigPath = WriteConfig -Config $Response.config -PrivateKey $Keys.Private
Write-Host "Config written to $ConfigPath" -ForegroundColor Green

Write-Host "Installing WireGuard tunnel service..." -ForegroundColor Cyan
ReinstallTunnel -ConfigPath $ConfigPath
Write-Host "VPN is active on interface $InterfaceName." -ForegroundColor Green
