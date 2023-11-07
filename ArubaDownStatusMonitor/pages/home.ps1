New-UDPage -Url "/home" -Name "home" -Content {
Function getControllerAPStatus {
    param(
        $currentArubaID = $cache:dashinfo.$DashboardName.currentArubaID,
        $arubaIP = '10.185.11.220:4343'
    )
    
    $res = invoke-RestMethod -uri "https://$arubaIP/v1/configuration/showcommand?command=show+ap+database&UIDARUBA=$currentArubaID" -SkipCertificateCheck #-WebSession $session
    
    $res | Where-Object { $_.folder -notlike "*Controllers*" } | Select-Object -ExpandProperty Device
}


Function getAirwaveDownAPs {
    param(
        $currentArubaID = $cache:dashinfo.$DashboardName.currentArubaID,
        $AirwaveIP = 'lvs1-amp-01.net.paypalcorp.com:443'
    )
    
    $res = invoke-RestMethod -uri "https://$arubaIP/v1/configuration/showcommand?command=show+ap+database&UIDARUBA=$currentArubaID" -SkipCertificateCheck #-WebSession $session
    $res.'AP Database'
}


if (0) {
    $ControllerAPStatus = getControllerAPStatus -currentArubaID $cache:dashinfo.$DashboardName.currentArubaID -arubaIP $cache:dashinfo.$DashboardName.settingsObj.ControllerIP 
    $APDownDataExpanded = getAirwaveDownAPs -currentArubaID $cache:dashinfo.$DashboardName.currentArubaID -AirwaveIP $cache:dashinfo.$DashboardName.settingsObj.AirwaveIP 



    $targets = @()
    ForEach ($obj in $APDownDataExpanded | select-object Name, "IP Address", status ) {

        $target0 = $DailyDownReport | ? { $_.Device -eq $obj.Name -and $_.folder -notlike "*Controllers*" }

        if ($target0) {
            $targets += $obj
        }
    }

    $targets | add-member -MemberType NoteProperty -name "PingReply" -value $null -force
    $targets | add-member -MemberType NoteProperty -name "DateTested" -value $null -force
    $targets | add-member -MemberType NoteProperty -name "ActualStatus" -value $null -force
    $targets | add-member -memberType NoteProperty -name "Recomendations" -value $null -force


    foreach ($obj in $targets) {
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

    #$targets | export-csv -path .\ArubaDailyDown$(get-date -f yyyy-MM-dd).csv

}

#-------------------------------

New-UDGrid -Container -Content {

    #invoke-RestMethod -uri "https://10.185.11.220:4343/v1/configuration/showcommand?command=show+ap+database&UIDARUBA=$arubaId" -SkipCertificateCheck #-WebSession $session

    $layout = '{"lg":[{"w":1,"h":1,"x":6,"y":0,"i":"grid-element-debugit","moved":false,"static":false},{"w":3,"h":1,"x":3,"y":0,"i":"grid-element-currentArubaID","moved":false,"static":false},{"w":3,"h":1,"x":0,"y":0,"i":"grid-element-currentAirwaveID","moved":false,"static":false},{"w":12,"h":15,"x":0,"y":1,"i":"grid-element-tabs1","moved":false,"static":false}]}'
    New-UDGridLayout -id "grid_layout1" -layout $layout -Content { # add the '-design' flag to temporarily to obtain json layout
        
        New-UDButton -id debugit -Text "debug" -OnClick { Debug-PSUDashboard }
        #New-UDTab
        
        New-UDTextbox -Id 'currentArubaID' -Value $cache:dashinfo.$DashboardName.currentArubaID -Disabled -Placeholder "Current Aruba ID: NONE" -FullWidth 
        New-UDTextbox -Id 'currentAirwaveID' -Value $cache:dashinfo.$DashboardName.currentAirwaveID -Disabled -Placeholder "Current Airwave ID: NONE" -FullWidth 

                
        New-UDTabs -Tabs {

            New-UDTab -Text "Table" -Id 'Tab1' -Content {
                new-udcard -id "Table.card" -Content { 

                    $currentArubaID = $cache:dashinfo.$DashboardName.currentArubaID
                    $currentAirwaveID = $cache:dashinfo.$DashboardName.currentAirwaveID
                    
                    

                }
            }

            New-UDTab -Text "Site Check" -Id 'Tab2' -Content {
                New-UDElement -Tag div -Id 'tab2Content' -Content { "Tab2Content" }
            }
            New-UDTab -Text "Stats / Charts" -Id 'Tab3' -Content {
                New-UDElement -Tag div -Id 'tab3Content' -Content { "Tab3Content" }
            }
        } -Id 'tabs1'

    }
}
} -Description "home" -Title "home" -Generated