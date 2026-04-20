#Run as Administrator

function CheckPrivileges() {
    $IsAdmin = [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$IsAdmin) {
        Write-Host "Permissions insufficient, Make sure you are running script with Admin privileges" -ForegroundColor Red
        exit 1
    }
    
}

function CheckWireguardInstallation() {
    $IsPathExist = (Test-Path "C:\Program Files\WireGuard\wireguard.exe") -and (Test-Path "C:\Program Files\WireGuard\wg.exe")
    $IsCliAvailable = (Get-Command wireguard -ErrorAction SilentlyContinue) -or (Get-Command wg -ErrorAction SilentlyContinue)

    if ($IsCliAvailable -and $IsPathExist) {
        return $true
    }
    elseif ($IsPathExist) {
        #Program Files\WireGuard\wireguard.exe
    }
    else {
        Write-Output "Make sure Wireguard installed properly"
        exit 1
    }
}

function TryToInstallWireguard() {
    $IsChocolateyInstalled = (Get-Command choco.exe -ErrorAction SilentlyContinue)

    try {
        winget install -e --id WireGuard.WireGuard
    }
    catch {
        try {
            choco install wireguard -y
        }
        catch {
            ##More options
        }
    }
    finally {
        Write-Output "Please download Wireguard client manually, run script afterwards"
    }
}



#Rest of the configuration
####This file is being used as a template