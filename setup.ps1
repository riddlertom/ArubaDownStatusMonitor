#Requires -Modules Universal -RunAsAdministrator 
<#

install-Module Universal -AcceptLicense -Force # -RequiredVersion 2.3.2
Install-PSUServer


#>

#eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJodHRw...
$token = '' #

if(!$token){
    Write-Error "Please update this file with an admin token. This is found by navigating to: http://localhost:5000/admin/security/tokens > then copying the admin token"
    Pause
    return 
    exit
}

$conn =@{
    ComputerName = 'http://localhost:5000';
    AppToken = $token;
}
Connect-PSUServer @conn 
 


#Get-PSUApp
#New-PSUApp -Name "ArubaDownStatusMonitor" -FilePath "dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1" -BaseUrl "/ArubaMonitor" -Authenticated -AutoDeploy
#>> dir\dashboards.ps1


