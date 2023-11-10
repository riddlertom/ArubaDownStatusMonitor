
#region: PREINIT

#setup shared cache and paths constants
$dashPath = $PSScriptRoot
$DashboardName = split-path $dashPath -Leaf

if (!$cache:dashinfo) { $cache:dashinfo = @{} }
if (!$cache:dashinfo.$DashboardName) { $cache:dashinfo.$DashboardName = @{} }
if (!$cache:dashinfo.$DashboardName.dashPath) { $cache:dashinfo.$DashboardName.dashPath = $dashPath }

if (!$cache:dashinfo.$DashboardName.SettingsDb) { $cache:dashinfo.$DashboardName.SettingsDb = $cache:dashinfo.$DashboardName.dashPath + "\arubaSettings.json" }
if (!$cache:dashinfo.$DashboardName.Key) { $cache:dashinfo.$DashboardName.Key = @(15..0) }


#region:######## FUNCTIONS ###########################

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
                    
                    $encStr = $settingsObj.$settingsId | ConvertFrom-SecureString $cache:dashinfo.$DashboardName.Key
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
                $fileContents = ''
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

            }

            if ($settingsObj.$settingsId) {
                
                # decode pass strings and replace with casted secureobjs
                if ($settingsId -like "*pass*" -and $settingsObj.$settingsId -is [string]) {
                
                    $encStr = $settingsObj.$settingsId

                    #$encStr = "76492d1...ANwA="
                    $SecurStrObj = ($encStr | ConvertTo-SecureString -Key $cache:dashinfo.$DashboardName.Key)
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

            $encStr = $propertyValue | ConvertTo-SecureString -AsPlainText -Force |  ConvertFrom-SecureString $cache:dashinfo.$DashboardName.Key                
            $SecurStrObj = ($encStr | ConvertTo-SecureString $cache:dashinfo.$DashboardName.Key)
            $cache:dashinfo.$DashboardName.settingsObj.$propertyName = $SecurStrObj
        }
        else {
            #$cache:dashinfo.$DashboardName.settingsObj.$propertyName = $propertyValue 
        }

    }


    #auth sources
    Function GetArubaAirwaveAuth {
        <#
        .SYNOPSIS
            returns a websession with a cookie containing the Airwave token id for subsequent calls
            Note: This won't re-prompt to auth if a previously invoked cookie is newer than the CookieMaxAgeMins.
    
        .DESCRIPTION
            API Authentication
            AirWave requires all API requests to pass a /LOGIN authentication gateway, then obtain a cookie and token called X-BISCOTTI.
            AirWave API requests must to have this cookie and token in the request header to complete authentication and also prevent cross-site request forgery (CSRF) attacks.
        
            The following code example can be used for AirWave API authentication.
        
    
        .LINK
        https://www.arubanetworks.com/techdocs/AirWave/82152/webhelp/Content/API%20Guide/API%20Guide.htm
    
        .EXAMPLE
            # Call a brand new connection
            $AuthedSession = GetArubaAirwaveAuth -airwaveNameIPPort 'somehost.domain.com:4343' -CookieMaxAgeMins $(New-TimeSpan -Days 365|select -expand TotalMinutes) #-force
    
            # Re-call a connection with previously authed websession cookie
            $AuthedSession = GetArubaAirwaveAuth -airwaveNameIPPort 'somehost.domain.com:4343' -session $AuthedSession -CookieMaxAgeMins $(New-TimeSpan -Days 365|select -expand TotalMinutes) #-force
    
            # Extract ID
            $arubaId = $AuthedSession.cookies.GetAllCookies().value
    
            #now get an Aruba xml daily down report
            $xml = Invoke-RestMethod -uri $uri -SkipCertificateCheck -WebSession $AuthedSession
        #>
        param(
    
            #target controller System.Net.DnsEndPoint
            [string]
            $airwaveNameIPPort,
    
    
            #Used to compare cookie age (or reuse in other calls if needed)
            [Microsoft.PowerShell.Commands.WebRequestSession]
            $session,
    
            #how many minutes is the cookie valid for. (Default = year)
            [double]
            $CookieMaxAgeMins = $(New-TimeSpan -Days 365 | select -expand TotalMinutes),
    
            #Ignore previously cached Cookies
            [switch]
            $force
        )
       
    
        $domain = $airwaveNameIPPort -split ':' | select -First 1
    
        #check for a previously non-expired cookie
        if ($session) {
           
            [array]$existingCookie = $session.Cookies.getAllCookies() | ? { $_.Domain -eq $domain }
    
            if ($existingCookie.count -eq 1 -and $force -ne $true) {
    
                $priorCookieIsValid = $existingCookie.TimeStamp.AddMinutes($CookieMaxAgeMins) -gt [datetime]::Now
               
                if ($priorCookieIsValid) {
                   
                    write-host "Returning previously Cached Cookie session"
                    return $session
                }
            }
        }
    
    
        #Obtain a fresh auth id token from scratch.
        write-host "Attempting to retrieve new Cookie"
    
        [pscredential]$account = Get-Credential
        $AuthAccount = $account.username
        $clearpw = $account.GetNetworkCredential().Password
       
    
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession # overwrite cookies with blank session
    
        #setup body params
        $body = @{
            "credential_0" = $creds.UserName;
            "credential_1" = $passw;
            "destination"  = '/index.html'; # '/'; # was also seen in examples
            #'login'="Log In"; # was also seen in examples
        }
            
        # setup args for irm call
        $params = @{
            'uri'                  = "https://$($airwaveNameIPPort)/LOGIN'";
            'Method'               = 'Post';
            'SkipCertificateCheck' = $true;
            'Body'                 = $body;
            'websession'           = $session;
            'ContentType'          = 'application/x-www-form-urlencoded;charset=UTF-8';
        }
        $AuthResult = Invoke-RestMethod @params
       
        return $session
    }

    Function GetArubaControllerAuth {
        <#

        .SYNOPSIS
            Returns an auth session containing a token id from an Aruba controller.
            Note: When providing a prior $session, this func won't attempt to re-auth if a previously invoked cookie is newer than the $CookieMaxAgeMins 
            
        .EXAMPLE
            # Call a brand new connection
            $AuthedSession = GetArubaControllerAuth -account $account -ControllerNameIpPort 'somehost.domain.com:4343' -CookieMaxAgeMins $(New-TimeSpan -Days 365|select -expand TotalMinutes) #-force
    
            # Re-call a connection with previously authed websession cookie without reAuthing
            $AuthedSession = GetArubaControllerAuth -account $account -ControllerNameIpPort 'somehost.domain.com:4343' -session $AuthedSession -CookieMaxAgeMins $(New-TimeSpan -Days 365|select -expand TotalMinutes) #-force
    
        #>
        param(
    
            #target controller
            [string]
            $ControllerNameIpPort = "10.185.11.220",
    
    
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
       
        
        $domain = $airwaveNameIPPort -split ':' | select -First 1

        #check for a previously non-expired cookie
        if ($session) {

            [array]$existingCookie = $session.Cookies.getAllCookies() | ? { $_.Domain -eq $domain }
        
            if ($existingCookie.count -eq 1 -and $force -ne $true) {
        
                $priorCookieIsValid = $existingCookie.TimeStamp.AddMinutes($CookieMaxAgeMins) -gt [datetime]::Now
            
                if ($priorCookieIsValid) {
                
                    write-host "Returning previously Cached Cookie"
                    return $session
                }
            }
        }
        
        
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession # overwrite cookies with blank session
        
    
    
        #Obtain a fresh auth id token from scratch.
        write-host "Attempting to retrieve new Cookie"
    
        if (!$account) { [pscredential]$account = Get-Credential }

        $AuthAccount = $account.username
        $clearpw = $account.GetNetworkCredential().Password
       
        $params = @{
            'uri'                  = "https://$ControllerNameIpPort/v1/api/login";
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

    # data sources

}

#endregion #######################################

#endregion


#region: INIT

# load settings functions
if (!(Test-Path function:priv_loadSettings)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }

#load settings page backings
$settingsObj = priv_loadSettings -settingsFile $cache:dashinfo.$DashboardName.SettingsDb     # this will populate $cache:dashinfo.$DashboardName.settingsObj = (from file or local cache)


# Set any needed defaults
if (!$cache:dashinfo.$DashboardName.settingsObj.ReportRetentionDays) { $cache:dashinfo.$DashboardName.settingsObj.ReportRetentionDays = 365 }
if (!$cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory) { $g = "$($cache:dashinfo.$DashboardName.dashPath)\reportsData"; $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory = $g }
if ($cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce -eq $null) { $cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce = $false }
if ($cache:dashinfo.$DashboardName.settingsObj.ControllerisForce -eq $null) { $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce = $false }


# if this is the very first run post-setup, persist initial settingsobj to disk
$FileExists = $null
$settingsFile = $cache:dashinfo.$DashboardName.SettingsDb
try { $FileExists = test-path $settingsFile -ea 0 }catch {}
if (!$FileExists) {
    try {
        $nullme = priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.SettingsDb
        Show-UDToast -Duration 4000 -Message "Initialized settings file to: $settingsFile"
    }
    catch {
        Write-Error $_
    }
}

#endregion


#region: MAIN



$title = 'ArubaDown Status Monitor'
New-UDApp -Title $title -Pages @(
    Get-UDPage -Name 'Home'
    Get-UDPage -Name 'Settings'

)



#schedule api scraping to happen each day
$cache:dashinfo.$DashboardName.GetAPIdataSB_scheduledEndpoint = {

    $now = get-date
    if ($now.hour -eq 8) {
        #this is a hack to workaround new-udschedule -cron *possibly* not working properly.

        if (!(Test-Path function:priv_loadSettings)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
    
        $res = loadHistoricalDB -reportsDir $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory -Force
        makeHistoricalDbGrid -HistoricalDB $res
    
        $cache:dashinfo.$DashboardName.GetAPIdataSB_ArubaControllerAPDatabase.invoke()
        saveToDb -recordType 'ArubaControllerAPDatabase'
    
        $cache:dashinfo.$DashboardName.GetAPIdataSB_airwaveReport.invoke()
        saveToDb -recordType 'airwaveReport'
        
        $overallrows = priv_makeOverallRows
        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'OverallState' -allrows $page:OverallState

        GenerateNodeDownStats

        saveToDb -recordType 'OverallState'

        #todo: test with ZERO user interaction over multiple days.
    }
        
}
$EndpointDaily = New-UDEndpoint -Schedule (New-UDEndpointSchedule -Every 1 -Hour) -Endpoint $cache:dashinfo.$DashboardName.GetAPIdataSB_scheduledEndpoint

#ez test
#$EndpointDaily = New-UDEndpoint -Schedule (New-UDEndpointSchedule -Every 1 -Second) -Endpoint { $now =get-date ;$cache:test2=$now; if($now.Second -like "*2*"){$cache:test = $now} }

#endregion