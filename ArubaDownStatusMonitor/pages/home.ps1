New-UDPage -Url "/home" -Name "home" -Content {
$cache:dashinfo.$DashboardName.HomeFunctionsSB = {

    Function GenerateNodeDownStats {
        param()

        Show-UDToast -Message "GenerateNodeDownStats Not Implemented"
    }

    Function loadFromApi {
        param(
            $recordType
        )

        # this should be stashed as an SB that could be updated by user vs hard coded here
        $sbstr = '$cache:dashinfo.$DashboardName.GetAPIdataSB_{0}' -f $recordType

        

        $Sb = iex $sbstr 
        $Sb.invoke() #icm
    }

    Function saveToDb {
        param(
            $recordType
        )
    
        $saveRows0 = (iex "`$page:$recordType") # | select -ExcludeProperty rendered*")

        $now = $saveRows0 | select -first 1 -ExpandProperty RenderedOriginTimeStamp
        if (!$now) {
            write-error "missing timestamp on record(s). Defaulting to saving csv file to today"
            $now = get-date
        }
   

        if (!$cache:dashinfo.$DashboardName.HistoricalDB.days.$($now.date).Keys) { $cache:dashinfo.$DashboardName.HistoricalDB.days.$($now.date) = @{} }
        if (!$cache:dashinfo.$DashboardName.HistoricalDB.days.$($now.date).$recordType.Keys) { $cache:dashinfo.$DashboardName.HistoricalDB.days.$($now.date).$recordType = @{} }

        $saveRows = $saveRows0 | select -ExcludeProperty rendered*
        $cache:dashinfo.$DashboardName.HistoricalDB.days.$($now.date).$recordType.$now = $saveRows

        try {

            $destPath = newRecordPath -Dirpath $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory -FileNameEnd "$recordType.csv" -datetime $now
            $saveRows | Export-Csv -LiteralPath $destPath 
            Show-UDToast -Message "Saved to: $destpath" -Duration 4000
        }
        catch { write-error $_ }
    }
    
    Function emitDaysRecordsGrid {
        param(

            $selectedDay = $session:selectedDay,
    
            [parameter()]
            [ValidateSet('airwaveReport', 'OverallState', 'ArubaControllerAPDatabase')]
            [string]
            $recordType,

            #optionally provide rows when not pulling from the historical db (e.g. generating overallState or scraping Apis today)
            $allrows
        )

        if (!$allrows) {
            $allrows = $cache:dashinfo.$DashboardName.HistoricalDB.days.$($session:selectedDay.day).$recordType.$($session:selectedDay.$recordType)
            $isnewRecords = $true
        }




        [array]$rowHeadersF = @()

        [array]$propNames = $allrows[0].psobject.properties.name

        if ($propNames -notcontains 'RenderedinternalGuid') {
            $allrows | % { add-member -InputObject $_ -MemberType NoteProperty -name "RenderedinternalGuid" -value (new-guid) -force }
        }

        if ($isnewRecords) {
            
            $allrows | % { add-member -InputObject $_ -MemberType NoteProperty -name "RenderedOriginTimeStamp" -value $session:selectedDay.$recordType -force }
        }
        else {
            $allrows | % { add-member -InputObject $_ -MemberType NoteProperty -name "RenderedOriginTimeStamp" -value (get-date) -force }
        }



        $propNames | % {             
            if ($_ -like "Rendered*") { continue }
            [array]$rowHeadersF += @{ field = $_; editable = $true ; Flex = 1.0 } 
        }


        
        
        $rowSBTemplate = '$Page:{0} | Out-UDDataGridData -TotalRows $Page:{0}.Length -Context $EventData' #$page:{0}Length
        $str = $rowSBTemplate -f $recordType #, $allrows.Length
        $LoadRowsSB = [scriptblock]::Create($str)


        $OnEdit0 = '

            $newrow = $EventData.newRow | select * -exclude Id
            $RenderedinternalGuid = $newRow.RenderedinternalGuid

            $i = 0
            $rowint = $null
            foreach ($row in $page:{0}) {
                                
                if ($row.RenderedinternalGuid -eq $RenderedinternalGuid) { 
                    $rowInt = $i; 
                    break
                }
                $i++
            }
            if ($rowint -ne $null) { $page:{0}[$rowint] = $newrow }
        ' -replace '\{0\}', $recordType
        $OnEditSB = [scriptblock]::Create($OnEdit0)
        

        #build/eval dynamic vars
        $setvar1 = '$page:{0} = $allrows; $page:{0}Headers = $rowHeadersF; $page:{0}LoadRowsSB = $LoadRowsSB; $page:{0}onEditSB = $OnEditSB' -f $recordType
        iex $setvar1
        

        New-UDDataGrid -id "$recordType.prop" -ShowQuickFilter -Columns (iex "`$page:$($recordType)Headers") -LoadRows (iex "`$page:$($recordType)LoadRowsSB") -ShowPagination -PageSize 10 -OnEdit  (iex "`$page:$($recordType)onEditSB") -RowsPerPageOptions @(10, 25, 50, 100, 200, 1000)
    }

    Function makeHistoricalDbGrid {
        #sets the latest day backing and generates user-configurable record for each recordDay
        param(
            $HistoricalDB
        )
    
        $res = $HistoricalDB
        if (!$res.days.Keys) {
    
            $Page:allrows = [PSCustomObject]@{Name = 'Value' }
            [array]$Page:rowHeadersF = @{ field = "Name"; editable = $true }
        }
        else {
    
            $Page:latestDay = $res.days.Keys | sort | select -Last 1
            
    
            $allrows = @()
            foreach ($date in $res.days.Keys) {
    
                $objprops = [ordered]@{}
                $objprops.day = $date
    
                $records = $res.days.$date.Keys
    
                $records | % { $objprops.$_ = $res.days.$date.$_.Keys }
    
                $obj = [pscustomobject]$objprops
                $allrows += $obj
            }
        
            if (!$session:selectedDay) { $session:selectedDay = $allrows | ? { $_.day -eq $Page:latestDay } }
            

            [array]$page:rowHeadersF = New-UDDataGridColumn -MinWidth 350 -Field 'Selector' -Render {
            
                $session:Historicalprop = $EventData                            
                New-UDButton -Text "Load" -OnClick { 
    
                    $session:selectedDay = $session:Historicalprop 
                    #                   $cache:selectedDay = $session:selectedDay
    
                    #sync-udelement
                    Show-UDToast -Duration 4000 -Message "Loaded day: $($session:Historicalprop.day)"
                }
            }
        
            #todo: scrape ALL record types names across all days.
            #todo: test drop down rendering for names
            #todo: ensure dayte sorting is working properly.
            $allrows[0].psobject.properties.name | % { [array]$page:rowHeadersF += @{ field = $_; editable = $true ; Flex = 1.0 } }
        
    
            $Page:allrows = $allrows
        }
    }

    function loadHistoricalDB {
        #Loads records files for backing of reportsdir datagrid
        param(
            [System.IO.DirectoryInfo]
            $reportsDir,
    
            [switch]
            $Force
        )
    
        #region:functions ####################
        Function priv_newDailyRecord {
    
            $dailyrecord = @{
            
                OverallState              = @{};        
                ArubaControllerAPDatabase = @{};        
                airwaveReport             = @{};
            }
            
            $dailyrecord
        }
    

        #endregion #####################
    
    
        if (!(test-path $reportsDir -ea 0)) { mkdir $reportsDir -Force }
    
        if ($csvfiles = dir "$reportsDir\*.csv" -ea 0) {}
        if (!$csvfiles) { write-error "No historical data was found in dir: $reportsDir"; return }
    
        if ($cache:dashinfo.$DashboardName.HistoricalDB -and !$Force) {
            $HistoricalDBObj = $cache:dashinfo.$DashboardName.HistoricalDB
        }
    
        #-------------------
    
        #build up $HistoricalDBObj by grouping records by day, then by type.
        
        #newDailyRecord
        $HistoricalDBObj = @{
            selectedDay = -1; # TODO: grab from metadata.json
            days        = @{};
        }
        foreach ($csvfile in $csvfiles) {
    
            $info = getRecordInfoFromFullPath -FullfilePath $csvfile
            
            if (!$HistoricalDBObj.days.$($info.dateObj.Date) ) { $HistoricalDBObj.days.$($info.dateObj.Date) = priv_newDailyRecord }
            if (!$HistoricalDBObj.days.$($info.dateObj.Date).$($info.fileType).Keys) { $HistoricalDBObj.days.$($info.dateObj.Date).$($info.fileType) = @{} } #TODO: sort somewhow into [ordered]?
            
            # TODO: add support for more than .csv files via handler
            $HistoricalDBObj.days.$($info.dateObj.Date).$($info.fileType).$($info.dateObj) = import-csv -LiteralPath $csvfile.FullName
        }
        
    
        #/#
    
        $cache:dashinfo.$DashboardName.HistoricalDB = $HistoricalDBObj
        return $HistoricalDBObj
    }
    #$res = loadHistoricalDB -reportsDir $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory #-Force

    Function newRecordPath {
        #generates a reversable full file path 
        param(
            $Dirpath,
            $FileNameEnd = 'file.csv',
            
            #optional
            [datetime]
            $datetime = $(get-date)
        )
        #set this up for easy record files naming
        $filestampT = '{0:yyyy-MM-dd hh.mm.ss}'
        $recordTemplate = "$($Dirpath)\$($filestampT)_{1}"
        
        $recordTemplate -f $datetime, $FileNameEnd
    
    }
    #newRecordPath -Dirpath $cache:dashinfo.$DashboardName.dashPath -FileNameEnd myfile.csv -datetime (get-date)

    Function getRecordInfoFromFullPath {
        # returns a date and type from a record fullpath
        param(
            [System.IO.FileInfo]
            $FullfilePath
        )

        $baseArr = $FullfilePath.baseName -split '_' 
        
        $dateStr0 = $baseArr | select -first 1
        $dateStr = $dateStr0 -replace '-', '/' -replace '\.', ':'

        @{
            dateObj  = [datetime]$dateStr;
            fileType = $baseArr | select -last 1;
        }
        
    }
    #$info = getRecordInfoFromFullPath -FullfilePath "C:\ProgramData\UniversalAutomation\Repository\dashboards\ArubaDownStatusMonitor\sampleData\2023-11-08 12.20.37_ArubaControllerAPDatabase.csv"
    #$info.dateObj
    #$info.fileType

    Function emitOperationsButtons {
        param(
            $recordType
        )
        New-UDPaper -Children {

            New-UDStack -Id 'overallButtonStack' -Content {

                New-UDButton -Text "Load From API" -OnClick (
                    iex ('{ 

                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                    $recordType = "{0}"
               
                    loadFromApi -recordType $recordType
                    }' -replace '\{0\}', $recordType)
                )

                New-UDButton -Text "Save to DB" -OnClick (
                    iex ('{ 

                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                    $recordType = "{0}"
               
                    saveToDb -recordType $recordType
                    }' -replace '\{0\}', $recordType)
                )
            }
        }
    }
    
    Function priv_makeOverallRows {

        
        $recordType = 'airwaveReport'
        $DailyDownReport = $cache:dashinfo.$DashboardName.HistoricalDB.days.$($session:selectedDay.day).$recordType.$($session:selectedDay.$recordType)
        
        $recordType = 'ArubaControllerAPDatabase'
        $ControllerAPStatus = $cache:dashinfo.$DashboardName.HistoricalDB.days.$($session:selectedDay.day).$recordType.$($session:selectedDay.$recordType)

        
        $targets = @()
        ForEach ($obj in $ControllerAPStatus | select-object Name, "IP Address", status ) {
    
            $target0 = $DailyDownReport | ? { $_.Device -eq $obj.Name -and $_.folder -notlike "*Controllers*" }
    
            if ($target0) {
                $targets += $obj
            }
        }
    
        $targets | add-member -MemberType NoteProperty -name "PingReply" -value $null -force
        $targets | add-member -MemberType NoteProperty -name "DateTested" -value $null -force
        $targets | add-member -MemberType NoteProperty -name "ActualStatus" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Recomendations" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Notes" -value $null -force

        $targets | add-member -memberType NoteProperty -name "Last 7 Days" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Last 14 Days" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Last 30 Days" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Last 90 Days" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Last 120 Days" -value $null -force
        $targets | add-member -memberType NoteProperty -name "Last 365 Days" -value $null -force
    
    
        #foreach  ($obj in $targets) {

        $targets | foreach-object -ThrottleLimit 10 -Parallel {

            $obj = $_

            $obj.datetested = Get-Date
            $obj.PingReply = Test-NetConnection -computername $obj.'ip address' | Select-Object -ExpandProperty PingSucceeded
            
            $obj.ActualStatus = if ($obj.PingReply -eq "True" -and $obj.Status -like "UP*") {
                "Up"
            }
            else {
                "Down"
            }
            $obj.Recomendations = if ($obj.PingReply -eq "True" -and $obj.Status -like "UP*") {
                "None"
            }
            else {
                "Reset Switch Port"
            }
    
        }

    
        [array]$rowHeadersF = New-UDDataGridColumn -Flex 1.0 -Field 'Selector' -Render {

            $session:temp = $EventData
            New-UDCheckBox  -OnChange {
                Show-UDToast -Duration 4000 -Message "selected : $($session:temp)"
            }
        }
        $targets[0].psobject.properties.name | % { [array]$rowHeadersF += @{ field = $_; editable = $true ; Flex = 1.0 } }
                

        $Page:OverallState = $targets
        $page:OverallStateHeaders = $rowHeadersF
        
        #$targets | export-csv -path .\ArubaDailyDown$(get-date -f yyyy-MM-dd).csv
    
        $targets
    }
    #$overallrows = priv_makeOverallRows
    
}

$cache:dashinfo.$DashboardName.GetAPIdataSB_airwaveReport = {

    if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString()}
              
    if ($cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce -and $false) {
        $params = @{
            airwaveNameIPPort = $cache:dashinfo.$DashboardName.settingsObj.AirwaveIP;
            session              = $cache:dashinfo.$DashboardName.AirwaveWebsession;
            CookieMaxAgeMins     = $(New-TimeSpan -Days 365 | select -expand TotalMinutes);
            account              = [pscredential]::new($cache:dashinfo.$DashboardName.settingsObj.AirwaveUser, $cache:dashinfo.$DashboardName.settingsObj.AirwavePass)
            force                = $cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce;
        }
        $cache:dashinfo.$DashboardName.AirwaveWebsession = GetArubaAirwaveAuth @params
    }

    if (!$cache:dashinfo.$DashboardName.AirwaveWebsession) { Write-Error "Unable to obtain token AirwaveWebsession"; return }

    #---------------------

    $res2 = Invoke-RestMethod -uri "https://$($cache:dashinfo.$DashboardName.settingsObj.AirwaveIP)/latest_report.xml?id=44754" -websession $cache:dashinfo.$DashboardName.AirwaveWebsession -SkipCertificateCheck
    $allrows = $res2.report.pickled_ap_uptime | ? { $_.'icmp_up_down_count' -ne 0 }
    <#
        Device,Group,Folder,"Device Uptime","Device Uptime is Reliable","Time Since Last Contact","Time Since Last Boot","SNMP Comm Uptime","SNMP Comm Up/Down Times","ICMP Comm Uptime","ICMP Comm Up/Down Times","HTTPS Comm Uptime","HTTPS Comm Up/Down Times"
        phx11-1-08,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 31 mins 39 secs",99.60%,1,99.60%,1,-,-
        phx14-1-wa02,"Controllers - North America","Top > Controllers - North America > Controllers - phx14",99.83%,Yes,"Comm is ok","19 hrs 48 mins 53 secs",99.74%,1,99.74%,1,-,-
        phx11-1-11,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 31 mins 39 secs",99.60%,1,99.60%,1,-,-
        phx14-1-01,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 32 mins 30 secs",99.60%,1,99.60%,1,-,-
        phx11-1-05,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 31 mins 35 secs",99.29%,1,99.29%,1,-,-
        phx14-1-02,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 32 mins 13 secs",99.60%,1,99.60%,1,-,-
        phx11-1-03,"Access Points - North America","Top > Access Points - North America > Access Points - phx14",100.00%,Yes,"Comm is ok","17 days 6 hrs 31 mins 38 secs",99.29%,1,99.29%,1,-,-
        oma3-1-wlc01-2,"Controllers - North America","Top > Controllers - North America > Controllers - oma2",0.00%,No,"9 days 19 hrs 33 mins 33 secs","Device Down",0.00%,0,100.00%,0,-,-
    
        #>
    
    emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'airwaveReport' -allrows $allrows #$page:ArubaControllerAPDatabase

    
    #Clear-UDElement -id 'airwaveReport.div'
    
    
    #<#

    $cache:GetAPIdataSB_airwaveReport_rows = $allrows

    set-udelement -id 'airwaveReport.div' -content {
        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB}
        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'airwaveReport' -allrows $cache:GetAPIdataSB_airwaveReport_rows #$page:ArubaControllerAPDatabase
    }
    #>
    
}

$cache:dashinfo.$DashboardName.GetAPIdataSB_ArubaControllerAPDatabase = {

    # load global functions
    if (!(Test-Path function:priv_loadSettings)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
    
    try {
        $params = @{
            ControllerNameIpPort = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP;
            session              = $cache:dashinfo.$DashboardName.ControllerWebsession;
            CookieMaxAgeMins     = $(New-TimeSpan -Days 365 | select -expand TotalMinutes);
            account              = [pscredential]::new($cache:dashinfo.$DashboardName.settingsObj.ControllerUser, $cache:dashinfo.$DashboardName.settingsObj.ControllerPass)
            force                = $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce;
        }
        $cache:dashinfo.$DashboardName.ControllerWebsession = GetArubaControllerAuth @params
        $domain = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP -split ':' | select -first 1
        $currentArubaCookie = $cache:dashinfo.$DashboardName.ControllerWebsession.Cookies.getAllCookies() | ? { $_.domain -eq $domain } | select -first 1
        $cache:dashinfo.$DashboardName.currentArubaID = $currentArubaCookie.value
    }
    catch { write-error $_ }

    $arubaId = $cache:dashinfo.$DashboardName.currentArubaID
    if (!$arubaId -or $cache:dashinfo.$DashboardName.ControllerWebsession) { Write-Error "Unable to obtain token/websession object(s)"; return }


    $uri = "https://$($cache:dashinfo.$DashboardName.settingsObj.ControllerIP)/v1/configuration/showcommand?command=show+ap+database&UIDARUBA=$arubaId" 

    $control = invoke-RestMethod -uri $uri -SkipCertificateCheck -WebSession $cache:dashinfo.$DashboardName.ControllerWebsession
    $allrows = $control.'AP Database' # TODO: VERIFY we don't need this: #| Where-Object { $_.folder -notlike "*Controllers*" } | Select-Object -ExpandProperty Device

    Clear-UDElement -id 'ArubaControllerAPDatabase.div'
    set-udelement -id 'ArubaControllerAPDatabase.div' -content {
        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'ArubaControllerAPDatabase' -allrows $allrows #$page:ArubaControllerAPDatabase
    }
    
    #sync-udelement -id 'overallOpsDiv' #update buttons if ever needed lookgs like this

}


if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

$res = loadHistoricalDB -reportsDir $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory #-Force

makeHistoricalDbGrid -HistoricalDB $res


#-------------------------------

#New-UDGrid -Container -Content {

New-UDRow -Id "mainrow" -Columns {

    New-UDColumn -Id "maincol1" -Size 12 -Content {

        $layout = '{"lg":[{"w":1,"h":1,"x":6,"y":0,"i":"grid-element-debugit","moved":false,"static":false},{"w":3,"h":1,"x":3,"y":0,"i":"grid-element-currentArubaID","moved":false,"static":false},{"w":3,"h":1,"x":0,"y":0,"i":"grid-element-currentAirwaveID","moved":false,"static":false},{"w":12,"h":16,"x":0,"y":1,"i":"grid-element-homeTabs","moved":false,"static":false}]}'
        New-UDGridLayout -id "grid_layout1" -layout $layout -Content { # add the '-design' flag to temporarily to obtain json layout
        
            New-UDButton -id debugit -Text "debug" -OnClick { Debug-PSUDashboard }
        
            New-UDTextbox -Id 'currentArubaID' -Value $cache:dashinfo.$DashboardName.currentArubaID -Disabled -Placeholder "Current Aruba ID: NONE" -FullWidth 
            New-UDTextbox -Id 'currentAirwaveID' -Value $cache:dashinfo.$DashboardName.currentAirwaveID -Disabled -Placeholder "Current Airwave ID: NONE" -FullWidth 

                
            New-UDTabs -Id 'homeTabs' -Tabs {

                New-UDTab -Text "Overall State" -Id 'Overall.tab' -Content {

                    #New-UDCard -Id 'Overall.tab.div' -Content {
                    New-UDElement -tag div -Id 'Overall.tab.div' -Content {

                        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                        New-UDExpansionPanelGroup -Id 'expandsionPanelGroup1' -Children {

                            New-UDExpansionPanel -Title "Operations" -Id 'expansionPanel1' -Content {

                                New-UDElement -tag div -id "overallOpsDiv" -Endpoint {

                                    New-UDPaper -Children {
                                        New-UDStack -Id 'overallButtonStack' -Content {

                                            New-UDButton -Text "Generate Grid" -OnClick { 
                                
                                                if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
                                
                                                $overallrows = priv_makeOverallRows
                                            
                                                #sync-udelement -id 'OverallState.prop'
                                            
                                                Clear-UDElement -id 'overallpropgrid.div'
                                                set-udelement -id 'overallpropgrid.div' -content {
                                                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
                                                    emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'OverallState' -allrows $page:OverallState
                                                }
                                                
                                                sync-udelement -id 'overallOpsDiv'
                                            }


                                            $recordType = 'OverallState'
                                            

                                            $HasOverallState = $session:selectedDay.$recordType | Measure-Object | select -ExpandProperty count
                                            $isdisabled = @{'disabled' = $true }
                                            if ($page:overallState -or $HasOverallState) {
                                                                                        
                                                $isdisabled = @{'disabled' = $false }                                                
                                            }


                                            #>
                            
                                            #New-UDButton -Text "Ping Targets" @isdisabled -OnClick { Debug-PSUDashboard }
                                            New-UDButton -Text "Generate NodeDown Stats" @isdisabled -OnClick { 
                                            
                                                GenerateNodeDownStats
                                            }

                                            New-UDButton -Text "Save to DB" @isdisabled -OnClick { 

                                                if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                                                $recordType = 'OverallState'
                                       
                                                saveToDb -recordType $recordType
                                            }
                                        
                                        }
                                    }
                                }
                            }

                            New-UDExpansionPanel -Active -Title "Data" -Id 'expansionPanel2' -Content {

                                new-udelement -tag div -id 'overallpropgrid.div' -Endpoint {

                                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
                                    
                                    $HasOverallState = $session:selectedDay.overallstate | Measure-Object | select -ExpandProperty count
                                    if ($HasOverallState) {
                                        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'OverallState'
                                    }
                                    else { "No Rows" }
                                }
                            }
                        }
                    }
                }

                New-UDTab -Id 'Controller.tab' -Text "Controller State" -Content {
                    
                    #New-UDCard -Id 'Controller.tab.div' -Content {
                    New-UDElement -tag div -Id 'Controller.tab.div' -Content {
                    
                        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                        New-UDExpansionPanelGroup -Id 'expandsionPanelGroup1' -Children {

                            New-UDExpansionPanel -Title "Operations" -Id 'expansionPanel1' -Content {

                                New-UDPaper -Children {
                                    emitOperationsButtons -recordType 'ArubaControllerAPDatabase'
                                }
                                
                            }

                            New-UDExpansionPanel -Active -Title "Data" -Id 'expansionPanel2' -Content {

                                new-udelement -tag div -id 'ArubaControllerAPDatabase.div' -Endpoint {
                                
                                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
                                    emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'ArubaControllerAPDatabase'
                                }

                            }
                        }

                    }
                }

                New-UDTab -Id 'Airwave.tab' -Text "Airwave State" -Content {
                    
                    #New-UDCard -Id 'Airwave.tab.div' -Content {
                    New-UDElement -tag div -Id 'Airwave.tab.div' -Content {

                        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                        New-UDExpansionPanelGroup -Id 'expandsionPanelGroup1' -Children {

                            New-UDExpansionPanel -Title "Operations" -Id 'expansionPanel1' -Content {

                                New-UDPaper -Children {
                                    emitOperationsButtons -recordType 'airwaveReport'
                                }
                                
                            }
                            
                            New-UDExpansionPanel -Active -Title "Data" -Id 'expansionPanel2' -Content {
                                
                                new-udelement -tag div -id 'airwaveReport.div' -Endpoint {

                                    if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }
                                    
                                    if($cache:GetAPIdataSB_airwaveReport_rows){
                                        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'airwaveReport'
                                    }else{
                                        emitDaysRecordsGrid -selectedDay $session:selectedDay -recordType 'airwaveReport' -allrows $cache:GetAPIdataSB_airwaveReport_rows

                                    }
                                }
                            }

                        }

                    }
                }


                New-UDTab -Id 'Historical.tab' -Text "Historical Runs" -Content {
                
                    New-UDCard -Id 'Historical.tab.div' -Content {
                        #New-UDElement -tag div -Id 'Historical.tab.div' -Content {
                    
                        if (!(Test-Path function:newRecordPath)) { iex $cache:dashinfo.$DashboardName.HomeFunctionsSB.ToString() }

                        #$res = loadHistoricalDB -reportsDir $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory #-Force

                        $LoadRowsSB = { Out-UDDataGridData -Data $Page:allrows -Total $Page:allrows.Length -Context $EventData }
                        New-UDDataGrid -id "Historical.prop" -Columns $page:rowHeadersF -LoadRows $LoadRowsSB -PageSize 200 #-OnEdit { Show-UDToast "Editing $Body" }

                    }

                }

            } 

        }
    }
}
} -Description "home" -Title "home" -Generated