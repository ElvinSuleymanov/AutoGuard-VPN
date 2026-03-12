#Architecture type for installation of executable from https://download.wireguard.com/windows-client/xxx
#Or via choco install wireguard 
#...
#Install Wireguard if it's not installed

if ((Get-Command wireguard -ErrorAction SilentlyContinue) -or (Get-Command wg -ErrorAction SilentlyContinue)) {
    Write-Output "WireGuard CLI is accessible."
} else {
    Write-Output "Binary not found in PATH."
    #installation or add to PATH
    #....
}

#Rest of the configuration


####This file is being used as a template