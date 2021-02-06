#####################################################
# Attaching a DHCP Relay service to Service/CSP port
#####################################################

# Input
Write-Host "`n> NSX-T Manager details" -ForegroundColor Blue
$nsxtmanager = Read-Host -Prompt "-> FQDN/IP"
$nsxtmanagerCredentials = Get-Credential -Message "-> Credential"

$logicalRouterName = Read-Host -Prompt "-> Router Name"
$interfaceName = Read-Host -Prompt "-> Interface Name"
$dhcpRelayName = Read-Host -Prompt "-> DHCP Relay Name"

# Global variables - API URLS
# Policy API
$nsxtGetLogicalRouters = "https://$nsxtmanager/api/v1/logical-routers/"
$nsxtGetLogicalRouterPorts = "https://$nsxtmanager/api/v1/logical-router-ports/"
$nsxtGetDHCPRelay = "https://$nsxtmanager/api/v1/dhcp/relays/"
$nsxtPutAttachDHCPRelay = "https://$nsxtmanager/api/v1/logical-router-ports/"

# Get Logical Routers
$nsxtGetRequest = $null
$nsxtGetRequest = Invoke-RestMethod -Uri $nsxtGetLogicalRouters -Authentication Basic -Credential $nsxtmanagerCredentials -Method Get -ContentType "application/json" -SkipCertificateCheck
$logicalRoutersInfo = $nsxtGetRequest.results

# Get Logical Router Ports info
$nsxtGetRequest = $null
$nsxtGetRequest = Invoke-RestMethod -Uri $nsxtGetLogicalRouterPorts -Authentication Basic -Credential $nsxtmanagerCredentials -Method Get -ContentType "application/json" -SkipCertificateCheck
$logicalRouterPortsInfo = $nsxtGetRequest.results

# Get DHCP Relays info
$nsxtGetRequest = $null
$nsxtGetRequest = Invoke-RestMethod -Uri $nsxtGetDHCPRelay -Authentication Basic -Credential $nsxtmanagerCredentials -Method Get -ContentType "application/json" -SkipCertificateCheck
$dhcpRelaysInfo = $nsxtGetRequest.results 

# Sanity checks# Check Router
Write-Host "`n> Sanity Check" -ForegroundColor Blue
$logicalRouter = $logicalRoutersInfo | Where-Object { $_.display_name -eq $logicalRouterName }
Write-Host "-> Router`t= $($logicalRouterName) - Found = " -ForegroundColor Yellow -NoNewline
if ($logicalRouter){
    Write-Host "TRUE - id= $($logicalRouter.id)" -ForegroundColor Green
} else {
    Write-Host "FALSE" -ForegroundColor Red
}

# Check Logical Port
$logicalPort = $logicalRouterPortsInfo | Where-Object { $_.display_name -match $interfaceName}
Write-Host "-> Logical Port`t= $($interfaceName) - Found = " -ForegroundColor Yellow -NoNewline
if ($logicalPort){
    Write-Host "TRUE - id= $($logicalPort.id)" -ForegroundColor Green
} else {
    Write-Host "FALSE" -ForegroundColor Red
}
Write-Host "-> Logical Port $($interfaceName) is connected to Router $($logicalRouterName) = " -ForegroundColor Yellow -NoNewline
if ($logicalPort.logical_router_id -eq $logicalRouter.id) {
    Write-Host "TRUE" -ForegroundColor Green
    $connected = $true
} else {
    Write-Host "FALSE" -ForegroundColor Red
    $connected = $false
}

# Check DHCP Relay
$dhcpRelay = $dhcpRelaysInfo | Where-Object { $_.display_name -eq $dhcpRelayName }
Write-Host "-> DHCP Relay`t= $($dhcpRelayName) - Found = " -ForegroundColor Yellow -NoNewline
if ($dhcpRelay){
    Write-Host "TRUE - id= $($dhcpRelay.id)" -ForegroundColor Green
} else {
    Write-Host "FALSE" -ForegroundColor Red
}

if ($logicalRouter -and $logicalPort -and $dhcpRelay -and $connected) {
    Write-Host "`n--> All parameters are validated ready to go <--" -ForegroundColor Green
    Write-Host "`n--> Press any key to proceed..." -ForegroundColor DarkGreen
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} else {
    Write-Host "`n----> Validate Input parameters and retry <-----" -ForegroundColor Red
    Exit
}

Write-Host "`n> Attaching DHCP Relay $($dhcpRelayName) to Service Port $($interfaceName) connected to Router $($logicalRouterName)" -ForegroundColor Blue

# Get Service Port current config
$servicePortConfig = $null
$url = $nsxtGetLogicalRouterPorts + $logicalPort.id
$servicePortConfig = Invoke-RestMethod -Uri $url -Authentication Basic -Credential $nsxtmanagerCredentials -Method Get -ContentType "application/json" -SkipCertificateCheck

# Build payload

# Check if there is already a DHCP config
if ($servicePortConfig."service_bindings"){
    $dhcpExistingSetup = $servicePortConfig."service_bindings" | Where-Object { ($_."service_id")."target_type" -eq "DhcpRelayService"}
    Write-Host "-> Interface - $($interfaceName) - already has DHCP Relay Service = $($dhcpExistingSetup."service_id"."target_display_name") attached" -ForegroundColor Red
    if ((Read-Host -Prompt "`n-> Want to keep the current setting (yes/no) (default: yes)") -eq "no") {
        # Remove any existing DHCP Relay config in the port
        $servicePortConfig."service_bindings" = $servicePortConfig."service_bindings" | Where-Object { ($_."service_id")."target_type" -ne "DhcpRelayService" }
    } else {
        Write-Host "`n--> KEEP CURRENT SETTINGS <--" -ForegroundColor Green
        Exit
    }
}

# Create service_bindings property if not there
#if (!($servicePortConfig."service_bindings")) {
    $servicePortConfig | Add-Member -Name "service_bindings" -MemberType NoteProperty -Value @() -ErrorAction SilentlyContinue
#}

$servicePortConfig."service_bindings" += ,@{ "service_id" = @{ `
    "target_display_name" = "$($dhcpRelay."display_name")" ;
    "is_valid" = $true ;
    "target_type" = "DhcpRelayService" ;
    "target_id" = "$($dhcpRelay."id")"
    }
}

$jsonPayload = ConvertTo-Json -InputObject $servicePortConfig -Depth 10
$url = $nsxtPutAttachDHCPRelay + $logicalPort.id
$putRequestResult = Invoke-RestMethod -Uri $url -Authentication Basic -Credential $nsxtmanagerCredentials -Method Put -Body $jsonPayload `
    -ContentType "application/json" -Headers @{'X-Allow-Overwrite' = 'true'} -SkipCertificateCheck

# Validate Change
# Get Service Port current config
Write-Host "`n> Checking result..." -ForegroundColor Blue

$dhcpRelaySetup = $putRequestResult."service_bindings" | Where-Object { ($_."service_id")."target_type" -eq "DhcpRelayService" }

if ($dhcpRelaySetup."service_id"."target_display_name" -eq $dhcpRelayName) {
    Write-Host "-> DHCP Relay Sucessfully Attached" -ForegroundColor Green
    Write-Host "--> DHCP Relay $($dhcpRelaySetup."service_id"."target_display_name")" -ForegroundColor Green
    Write-Host "--> Service Port $($putRequestResult."display_name")" -ForegroundColor Green
    Write-Host "--> Router $($logicalRouterName)" -ForegroundColor Green
} else {
    Write-Host "-> DHCP Relay Configuration - Not Sucessfull" -ForegroundColor Red
}

                
