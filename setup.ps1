#Requires -RunAsAdministrator 

#helper script to setup web tooling

#quick check for files to be present
$thisPath = $PSScriptRoot
$dashpath = "$thisPath\ArubaDownStatusMonitor"
if (!(dir -ea 0 -LiteralPath "$thisPath\ArubaDownStatusMonitor")) { Write-Error "Couldn't find dashboard files at dir: $dashpath"; pause; return; exit; }


# region: setup universal if needed

    #what version of universal our dashboard was built on
    $buildVer = [version]'4.1.8'
    $module_universal = Get-Module -ListAvailable -name universal

    $installedVersionNotOK = $module_universal.Version -lt $buildVer

    if ( !$module_universal -or $installedVersionNotOK) {
        

        write-host "Installing missing Powershell Universal Module"
        try {

            install-Module Universal # -AcceptLicense -Force -RequiredVersion $buildVer
            Install-PSUServer
            write-host "Finished installing Powershell Universal"
        }
        catch {
            write-error $_
        }

        $module_universal2 = Get-Module -ListAvailable -name universal
        $installedVersionNotOK2 = $module_universal.Version -lt $buildVer
        if ( !$module_universal2 -or $installedVersionNotOK2) { Write-Error "Something went wrong during setup of Powershell Universal"; pause; return; exit }
    }else{
        write-host "Valid Powershell Universal Module Found with Version: $($module_universal.Version)"
    }

#endregion

#region: copy/enable dashboard

    #find paths
    $service = get-service -Name PowerShellUniversal
    if ( !$service -or !$service.BinaryPathName) { Write-Error "Something went wrong during setup of Powershell Universal"; pause; return; exit }
    $match = [regex]::Match($service.BinaryPathName,'^.*PowerShellUniversal')
    if(!$match){}

    $baseProgramsPath0 = $match.Value | select -first 1
    $baseProgramsPath = $baseProgramsPath0 | split-path
    $dashboardPath = "$baseProgramsPath\UniversalAutomation\Repository"
    if(!(test-path $dashboardPath -ea 0)){Write-Error "Unable to find path to Powershell Universal dashboard directory at: $dashboardPath"; pause; return; exit;}

    $dashboardsFile = "$baseProgramsPath\UniversalAutomation\Repository\dashboards.ps1"
    if(!(test-path $dashboardsFile -ea 0)){Write-Error "Unable to find expected file: $dashboardPath"; pause; return; exit;}

    #---------------------------

    # enable dash
    $dashInstalled = gc $dashboardsFile | ?{$_ -like "*dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1*"}
    if(!$dashInstalled){'New-PSUApp -Name "ArubaDownStatusMonitor" -FilePath "dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1" -BaseUrl "/ArubaMonitor" -Authenticated -AutoDeploy' >> $dashboardsFile}else{write-host "Found installed dashboard at: $dashboardsFile"}

    $dashboardAppDir = "$dashboardPath\dashboards"
    if(!(test-path $dashboardAppDir -ea 0)){Write-Error "Unable to find expected path: $dashboardAppDir"; pause; return; exit;}
    copy-item -Verbose -Recurse -LiteralPath $dashpath -Destination $dashboardAppDir -Force
    
    if(!$dashInstalled){restart-service -Name PowerShellUniversal -Verbose }

    Write-Host "Setup finished"

#endregion
