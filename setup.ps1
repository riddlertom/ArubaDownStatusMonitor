#Requires -RunAsAdministrator 
#Requires -Version 7

#todo does not support windows 5.1 powerhsell

#helper script to setup web tooling

#quick check for files to be present
$thisPath = $PSScriptRoot
$dashpath = "$thisPath\ArubaDownStatusMonitor"
if (!(dir -ea 0 -LiteralPath "$thisPath\ArubaDownStatusMonitor")) { Write-Error "Couldn't find dashboard files at dir: $dashpath"; pause; return; exit; }


#todo: mac check instuction needed?

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
        $installedVersionNotOK2 = $module_universal2.version -lt $buildVer
        if ( !$module_universal2 -or $installedVersionNotOK2) { Write-Error "[Check2] Something went wrong during setup of Powershell Universal"; pause; return; exit }
    }else{
        write-host "Valid Powershell Universal Module Found with Version: $($module_universal.Version)"
    }

#endregion

#region: copy/enable dashboard

    #find paths
    
    #$service = get-service -Name PowerShellUniversal #!$service.BinaryPathName
    $process = ps -Name Universal.Server | select -First 1
    if ( !$service -or !$process.Path) { Write-Error "Missing Powershell Universal service info"; pause; return; exit }
    $match = [regex]::Match($process.Path,'^.*PowerShellUniversal')
    if(!$match){}

    $baseProgramsPath0 = $match.Value | select -first 1
    $baseProgramsPath = $baseProgramsPath0 | split-path

    $repoPath = "$baseProgramsPath\UniversalAutomation\Repository"
    if(!(test-path $repoPath -ea 0)){mkdir $dashboardPath -force -verbose}
    #Write-Error "Unable to find path to Powershell Universal dashboard directory at: $repoPath"; pause; return; exit;}

    $dashboardPath = "$baseProgramsPath\UniversalAutomation\Repository\dashboards"
    if(!(test-path $dashboardPath -ea 0)){mkdir $dashboardPath -force -verbose}
    
    $unidotpath = "$baseProgramsPath\UniversalAutomation\Repository\.universal"
    if(!(test-path $unidotpath -ea 0)){mkdir $unidotpath -force -verbose}
    

    $dashboardsFile1 = "$baseProgramsPath\UniversalAutomation\Repository\dashboards.ps1"
    if(!(test-path $dashboardsFile -ea 0)){'' > $dashboardsFile}

    $dashboardsFile2 = "$baseProgramsPath\UniversalAutomation\Repository\.universal\dashboards.ps1"
    if(!(test-path $dashboardsFile2 -ea 0)){'' > $dashboardsFile2}
    #Write-Error "Unable to find expected file at: $dashboardPath"; pause; return; exit;}

    #---------------------------

    # enable dash
    #$dashInstalled = gc $dashboardsFile1 | ?{$_ -like "*dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1*"}
    #if(!$dashInstalled){'New-PSUApp -Name "ArubaDownStatusMonitor" -FilePath "dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1" -BaseUrl "/ArubaMonitor" -Authenticated -AutoDeploy' >> $dashboardsFile1}else{write-host "Found installed dashboard at: $dashboardsFile1"}

    $dashInstalled2 = gc $dashboardsFile2 | ?{$_ -like "*dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1*"}
    if(!$dashInstalled2){'New-PSUApp -Name "ArubaDownStatusMonitor" -FilePath "dashboards\ArubaDownStatusMonitor\ArubaDownStatusMonitor.ps1" -BaseUrl "/ArubaMonitor" -Authenticated -AutoDeploy' >> $dashboardsFile2}else{write-host "Found installed dashboard at: $dashboardsFile2"}


    $dashboardAppDir = "$dashboardPath"
    if(!(test-path $dashboardAppDir -ea 0)){Write-Error "Unable to find expected path: $dashboardAppDir"; pause; return; exit;}
    copy-item -Verbose -Recurse -LiteralPath $dashpath -Destination $dashboardAppDir -Force
    
    if(!$dashInstalled){Stop-Service -Name PowerShellUniversal -Verbose -PassThru | Start-Service -Verbose}

    Write-Host "Setup finished: navigate to http://localhost:5000/ArubaMonitor"

#endregion
