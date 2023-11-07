New-UDPage -Url "/settings" -Name "settings" -Content {
#settings-specfic names that we load/update
$cache:dashinfo.$DashboardName.settingsIds = 'ControllerIP,ControllerUser,ControllerPass,ControllerisForce,AirwaveIP,AirwaveUser,AirwavePass,AirwaveisForce,ReportsDirectory,ReportRetentionDays' -split ','

$cache:dashinfo.$DashboardName.settingsFunctionsSB = {
    Function priv_SaveSettingsFile {
        # Updates both the file settingsobj from cache
        param($settingsFile)

        $settingsIds = $cache:dashinfo.$DashboardName.settingsIds
        $settingsObj = $cache:dashinfo.$DashboardName.settingsObj


        #build a persistable object to save to disk (e.g. no securestrings / binary objects that won't convert easily to json)
        $settingsObj_persist = @{}
        foreach ($settingsId in $settingsIds) {

            if ($settingsId -like "*pass*" -and $settingsObj.$settingsId -is [securestring] ) {
                
                # encode pass strings to not be clear text
                if ($settingsObj.$settingsId -ne $null) {
                    
                    $encStr = $settingsObj.$settingsId | ConvertFrom-SecureString -Key @(15..0)
                    $settingsObj_persist.$settingsId = $encStr
                }
                else {
                    $settingsObj_persist.$settingsId = $null
                }
            }
            else {
                $settingsObj_persist.$settingsId = $settingsObj.$settingsId
            }
            
        }


        $fileContents = $settingsObj_persist | ConvertTo-Json

        try {

            set-content -LiteralPath $settingsFile -value $fileContents -encoding utf8 
            Show-UDToast -Duration 4000 -Message "Saved current settings to: $settingsFile" 
        }
        catch {

            Write-Error $_
        }

        return $settingsObj_persist
    }

    Function priv_loadSettings {
        #inits, reads, and loads settingsobj to the forms and cache
        param($settingsFile)

        $settingsIds = $cache:dashinfo.$DashboardName.settingsIds

        # on first load, read from file
        if (!$cache:dashinfo.$DashboardName.settingsObj) {

            $FileExists = $null
            try { $FileExists = test-path $settingsFile -ea 0 }catch {}
            if ($FileExists) {
                try {
                    $fileContents = gc $settingsFile -Encoding utf8
                    Show-UDToast -Duration 4000 -Message "Loaded settings from: $settingsFile"
                }
                catch {
                    <#Do this if a terminating exception happens#>
                    Write-Error $_
                }
                
            }
            else {
                try {
                    $fileContents = ''
                    set-content -value $fileContents -encoding utf8 -path $settingsFile
                    Show-UDToast -Duration 4000 -Message "Initialized settings to $settingsFile"
                }
                catch {
                    Write-Error $_
                }
            }

            $settingsObj = $fileContents | ConvertFrom-Json
            if (!$settingsObj) {
                $settingsObj = @{}
            
                foreach ($settingsId in $settingsIds) {
                    if (!$settingsObj.$settingsId) {
                        $settingsObj.$settingsId = ''
                    }
                }
            }
        }
        else {
            $settingsObj = $cache:dashinfo.$DashboardName.settingsObj
        }


        #---------------------


        #finally: convert/format to binary/class (we refresh / sync-udelements in other areas of the program)
        foreach ($settingsId in $settingsIds) {
            

            #cast bools
            if ($settingsId -like "*isForce*") {

                if (!$settingsObj.$settingsId) {

                    $settingsObj.$settingsId = $false
                }
                else {
                    $settingsObj.$settingsId = [bool]::parse($settingsObj.$settingsId)
                }

                #Set-UDElement -Id $settingsId -Properties @{value = $settingsObj.$settingsId }
            }

            if ($settingsObj.$settingsId) {

                #Set-UDElement -Id $settingsId -Properties @{value = $settingsObj.$settingsId }
                
                
                # decode pass strings and replace with casted secureobjs
                if ($settingsId -like "*pass*" -and $settingsObj.$settingsId -is [string]) {
                
                    $encStr = $settingsObj.$settingsId

                    #$encStr = "76492d1...ANwA="
                    $SecurStrObj = ($encStr | ConvertTo-SecureString -key @(15..0))
                    $settingsObj.$settingsId = $SecurStrObj
                }
                
            }

        }

        #save to cache for other calls
        $cache:dashinfo.$DashboardName.settingsObj = $settingsObj

        
        return $settingsObj
    }

    function priv_setpassword {
        #updates securee string from password fields
        param(
            $propertyName,
            $propertyValue
        )
      
        if ($propertyValue -ne $null) {

            $encStr = $propertyValue | ConvertTo-SecureString -AsPlainText -Force |  ConvertFrom-SecureString -Key @(15..0)                
            $SecurStrObj = ($encStr | ConvertTo-SecureString -key @(15..0))
            $cache:dashinfo.$DashboardName.settingsObj.$propertyName = $SecurStrObj
        }
        else {
            #$cache:dashinfo.$DashboardName.settingsObj.$propertyName = $propertyValue 
        }

    }

    Function GetArubaAuth {
        <#
            Returns an Aruba token id from a controller.
            Note: This won't re-auth if a previously invoked cookie is newer than the CookieMaxAgeMins.
        #>
        param(
    
            #target controller
            [ipaddress]
            $ControllerIP = "10.185.11.220",
    
    
            #Used to compare cookie age (or reuse in other calls if needed)
            [Microsoft.PowerShell.Commands.WebRequestSession]
            $session,
    
            #how many minutes is the cookie valid for. (Default = year)
            [double]
            $CookieMaxAgeMins = $(New-TimeSpan -Days 365 | select -expand TotalMinutes),

            #User/pass that can auth to Aruba
            [pscredential]
            $account,
    
            #Ignore previously cached Cookies
            [switch]
            $force
        )
       
    
        #check for a previously non-expired cookie
        if ($session) {

            [array]$existingCookie = $session.Cookies.getAllCookies() | ? { $_.Domain -eq "$ControllerIP" }
        
            if ($existingCookie.count -eq 1 -and $force -ne $true) {
        
                $priorCookieIsValid = $existingCookie.TimeStamp.AddMinutes($CookieMaxAgeMins) -gt [datetime]::Now
            
                if ($priorCookieIsValid) {
                
                    write-host "Returning previously Cached Cookie"
                    return $existingCookie.Value
                }
            }
        }
        
        if (!$priorCookieIsValid) {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession # overwrite cookies with blank session
        }
    
    
        #Obtain a fresh auth id token from scratch.
        write-host "Attempting to retrieve new Cookie"
    
        if (!$account) { [pscredential]$account = Get-Credential }

        $AuthAccount = $account.username
        $clearpw = $account.GetNetworkCredential().Password
       
        $params = @{
            'uri'                  = "https://$($ControllerIP):4343/v1/api/login";
            'Method'               = 'Post';
            'SkipCertificateCheck' = $true;
            #'Headers' = @{"aruba-cookie"=$null};
            'Body'                 = "username=$AuthAccount&password=$clearpw";
            'websession'           = $session;
        }
        $AuthResult = Invoke-RestMethod @params
    
        write-host "Got Aruba token: $($AuthResult.UIDARUBA)"
        return $session
    }

    <#page paths
        $PageDir = $PSScriptRoot
        $cache:debugit = $PageDir
        $dashPath = split-path $PageDir -Parent
        $DashboardName = split-path $dashPath -Leaf 
    #>

}

#------------------   

if (!(Test-Path function:priv_loadSettings)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }

#hardcoded configFile

# ensure slow-loading endpoint runs before we try to access stored paths
if (!$cache:dashinfo.$DashboardName.dashPath) {

    Show-UDToast -Duration 10 -Message "loading config file..."
    $i = 0
    while ($i -lt 10) {
        $i++

        sleep -Seconds 1
    }
    Hide-UDToast
}

$settingsFile = $cache:dashinfo.$DashboardName.dashPath + "\arubaSettings.json"
#$settingsFile = $dashPath + "\arubaSettings.json"
$settingsObj = priv_loadSettings -settingsFile $settingsFile
$cache:dashinfo.$DashboardName.settingsObj.SettingsDb = $settingsFile



#default to 365 if blank
if (!$cache:dashinfo.$DashboardName.settingsObj.ReportRetentionDays) { $cache:dashinfo.$DashboardName.settingsObj.ReportRetentionDays = 365 }

New-UDGrid -Container -Content {

    $layout = '{"lg":[{"w":11,"h":4,"x":0,"y":0,"i":"grid-element-expandsionPanelGroup1","moved":false,"static":false}]}'
    New-UDGridLayout -id "grid_layout" -layout $layout -Content { # add the '-design' flag to temporarily to obtain json layout
            
        #New-UDButton -Text "debug" -OnClick { Debug-PSUDashboard }


        New-UDExpansionPanelGroup -Id 'expandsionPanelGroup1' -Children {

            New-UDExpansionPanel -Title "Aruba controller" -Id 'expansionPanel1' -Content {

                new-udcard -id "controller.card" -Title "Controller" -Content { 

                    New-UDForm -SubmitText Save -Content {
        
                        New-UDTextbox -FullWidth -id 'ControllerIP' -label 'Controller IP:port' -icon (New-UDIcon -Icon server) -value $cache:dashinfo.$DashboardName.settingsObj.ControllerIP -placeholder '1.2.3.4:4343'
                        New-UDTextbox -FullWidth -Id 'ControllerUser' -Label "ControllerUser" -icon (New-UDIcon -Icon user) -value $cache:dashinfo.$DashboardName.settingsObj.ControllerUser -placeholder "user1"
                        New-UDTextbox -FullWidth -Id 'ControllerPass' -Label "ControllerPass" -Type password -icon (New-UDIcon -Icon key) -placeholder "**********"
                        
                        
                        New-UDCheckbox -Id 'ControllerisForce' -Label "Force" -Checked $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce
                        
                    } -OnSubmit {
                        if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
        
                        $cache:dashinfo.$DashboardName.settingsObj.ControllerIP = $EventData.ControllerIP
                        $cache:dashinfo.$DashboardName.settingsObj.ControllerUser = $EventData.ControllerUser
                        
                        $propertyName = 'ControllerPass'
                        if ($EventData.$propertyName) { priv_setpassword -propertyName $propertyName -propertyValue $EventData.$propertyName }
        
                        $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce = $EventData.ControllerisForce
        
                        $SavedObj = priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.settingsObj.SettingsDb
                    }
        
                    New-UDPaper -Children {
                        
                        New-UDButton -Text "Connect" -OnClick {
            
                            if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
            
                            $params = @{
                                ControllerIP     = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP;
                                session          = $cache:dashinfo.$DashboardName.websession;
                                CookieMaxAgeMins = $(New-TimeSpan -Days 365 | select -expand TotalMinutes);
                                account          = [pscredential]::new($cache:dashinfo.$DashboardName.settingsObj.ControllerUser, $cache:dashinfo.$DashboardName.settingsObj.ControllerPass)
                                force            = $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce;
                            }
                            $cache:dashinfo.$DashboardName.websession = GetArubaAuth @params
            
                            $cache:dashinfo.$DashboardName.currentArubaID = $cache:dashinfo.$DashboardName.websession.Cookies.getAllCookies().value | select -first 1
                            #Sync-UDElement -id currentArubaID
                            Set-UDElement -Id "currentArubaID" -Properties @{value = $cache:dashinfo.$DashboardName.currentArubaID }
            
                        }
                        New-UDTextbox -Id 'currentArubaID' -Value $cache:dashinfo.$DashboardName.currentArubaID -Disabled -Placeholder "NONE" -FullWidth 
                    }
        
                }

            } 


            New-UDExpansionPanel -Title "Aruba Airwave" -Content {
                new-udcard -id "Airwave.card" -title "Airwave" -Content {

                    New-UDForm -SubmitText Save -Content {
        
                        New-UDTextbox -FullWidth -id 'AirwaveIP' -label 'Airwave IP:port' -icon (New-UDIcon -Icon server) -value $cache:dashinfo.$DashboardName.settingsObj.AirwaveIP -placeholder '1.2.3.4:4343'
                        New-UDTextbox -FullWidth -Id 'AirwaveUser' -Label "AirwaveUser" -icon (New-UDIcon -Icon user) -value $cache:dashinfo.$DashboardName.settingsObj.AirwaveUser -placeholder "user1"
                        New-UDTextbox -FullWidth -Id 'AirwavePass' -Label "AirwavePass" -Type password -icon (New-UDIcon -Icon key) -placeholder "**********"
                        New-UDCheckbox -Id 'AirwaveisForce' -Label "Force" -Checked $cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce
                    } -OnSubmit {
        
                        if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
        
                        $cache:dashinfo.$DashboardName.settingsObj.AirwaveIP = $EventData.AirwaveIP
                        $cache:dashinfo.$DashboardName.settingsObj.AirwaveUser = $EventData.AirwaveUser
        
                        $propertyName = 'AirwavePass'
                        if ($EventData.$propertyName) { priv_setpassword -propertyName $propertyName -propertyValue $EventData.$propertyName }
                        
                        $cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce = $EventData.AirwaveisForce
        
                        $savedobj = priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.settingsObj.SettingsDb
                    }
        
                    New-UDPaper -Children {
                        
                        New-UDButton -Text "Connect" -OnClick {
            
                            if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
                            
                            #todo some IRM call here?
            
                            $cache:dashinfo.$DashboardName.currentAirwaveID = $cache:dashinfo.$DashboardName.websession.Cookies.getAllCookies().value | select -first 1
                            #Sync-UDElement -id currentArubaID
                            Set-UDElement -Id "currentAirwaveID" -Properties @{value = $cache:dashinfo.$DashboardName.currentAirwaveID }
            
                        }
                        New-UDTextbox -Id 'currentAirwaveID' -Value $cache:dashinfo.$DashboardName.currentAirwaveID -Disabled -Placeholder "NONE" -FullWidth 
                    }
                    
                }
            } -Id 'expansionPanel2'

            New-UDExpansionPanel -Title "Databases" -Content { 
               
                new-udcard -id "Databases.card" -title "Databases" -Content {

                    New-UDForm -SubmitText Save -Content {

                        New-UDTextbox -FullWidth -id 'ReportsDirectory' -label 'ReportsDirectory' -icon (New-UDIcon -Icon Database) -value $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory -placeholder 'c:\path\to\CSV\Dir | \\unc\path\to\CSV\Dir'
                        New-UDTextbox -FullWidth -id 'ReportRetentionDays' -label 'ReportRetentionDays' -icon (New-UDIcon -Icon Database) -value $cache:dashinfo.$DashboardName.settingsObj.ReportRetentionDays -placeholder '365'
                        New-UDTextbox -FullWidth -id 'SettingsDb' -label 'Settings Db' -icon (New-UDIcon -Icon Database) -value $cache:dashinfo.$DashboardName.settingsObj.SettingsDb -placeholder '\\unc\path\to\shared.json' -Disabled
                    } -OnSubmit {

                        if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }

                        $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory = $EventData.ReportsDirectory
                        #$cache:dashinfo.$DashboardName.settingsObj.SettingsDb = $EventData.SettingsDb
                
                        priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.settingsObj.SettingsDb
                    }

                } 
            } -Id 'expansionPanel3'
        } 
    }
}
} -Title "Settings" -Generated -Layout (
New-UDPageLayout -Large @(
	New-UDItemLayout -Id 'df737398-3672-4e06-bae6-e59ae52a7b29' -Row 0 -Column 0 -RowSpan 1 -ColumnSpan 1
) -Medium @(
) -Small @(
	New-UDItemLayout -Id 'df737398-3672-4e06-bae6-e59ae52a7b29' -Row 0 -Column 0 -RowSpan 1 -ColumnSpan 1
	New-UDItemLayout -Id 'c8628625-0e96-4402-bbae-c5f07482334b' -Row 1 -Column 0 -RowSpan 1 -ColumnSpan 1
) -ExtraSmall @(
) -ExtraExtraSmall @(
	)
)