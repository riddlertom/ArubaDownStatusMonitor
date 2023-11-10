New-UDPage -Url "/settings" -Name "settings" -Content {
New-UDGrid -Container -Content {

    $layout = '{"lg":[{"w":11,"h":4,"x":0,"y":0,"i":"grid-element-expandsionPanelGroup1","moved":false,"static":false}]}'
    New-UDGridLayout -id "grid_layout" -layout $layout -Content { # add the '-design' flag to temporarily to obtain json layout

        #New-UDButton -Text "debug" -OnClick { Debug-PSUDashboard }


        New-UDExpansionPanelGroup -Id 'expandsionPanelGroup1' -Children {

            New-UDExpansionPanel -Title "Aruba controller" -Id 'expansionPanel1' -Content {

                new-udcard -id "controller.card" -Title "Aruba Controller" -Content { 

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
        
                        $SavedObj = priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.SettingsDb
                    }
        
                    New-UDPaper -Children {
                        
                        New-UDButton -Text "Connect" -OnClick {
            
                            if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
           
                            $params = @{
                                ControllerNameIpPort     = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP;
                                session          = $cache:dashinfo.$DashboardName.ControllerWebsession;
                                CookieMaxAgeMins = $(New-TimeSpan -Days 365 | select -expand TotalMinutes);
                                account          = [pscredential]::new($cache:dashinfo.$DashboardName.settingsObj.ControllerUser, $cache:dashinfo.$DashboardName.settingsObj.ControllerPass)
                                force            = $cache:dashinfo.$DashboardName.settingsObj.ControllerisForce;
                            }
                            $cache:dashinfo.$DashboardName.ControllerWebsession = GetArubaControllerAuth @params
            
                            $domain = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP -split ':' | select -first 1
                            $currentArubaCookie = $cache:dashinfo.$DashboardName.ControllerWebsession.Cookies.getAllCookies() | ?{$_.domain -eq $domain} | select -first 1
                            $cache:dashinfo.$DashboardName.currentArubaID = $currentArubaCookie.value
                            
                            #Sync-UDElement -id currentArubaID
                            Sync-UDElement -Id "currentArubaID" #-Properties @{value = $cache:dashinfo.$DashboardName.currentArubaID }
            
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
        
                        $savedobj = priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.SettingsDb
                    }
        
                    New-UDPaper -Children {
                        
                        New-UDButton -Text "Connect" -OnClick {
            
                            if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }
                            
                            $params = @{
                                ControllerNameIpPort = $cache:dashinfo.$DashboardName.settingsObj.AirwaveIP;
                                session          = $cache:dashinfo.$DashboardName.AirwaveWebsession;
                                CookieMaxAgeMins = $(New-TimeSpan -Days 365 | select -expand TotalMinutes);
                                account          = [pscredential]::new($cache:dashinfo.$DashboardName.settingsObj.AirwaveUser, $cache:dashinfo.$DashboardName.settingsObj.AirwavePass)
                                force            = $cache:dashinfo.$DashboardName.settingsObj.AirwaveisForce;
                            }
                            $cache:dashinfo.$DashboardName.AirwaveWebsession = GetArubaAirwaveAuth @params
            
                            $domain = $cache:dashinfo.$DashboardName.settingsObj.ControllerIP -split ':' | select -first 1
                            $currentArubaCookie = $cache:dashinfo.$DashboardName.AirwaveWebsession.Cookies.getAllCookies() | ?{$_.domain -eq $domain} | select -first 1
                            $cache:dashinfo.$DashboardName.currentAirwaveID = $currentArubaCookie.value
                            
                            #Sync-UDElement -id currentArubaID
                            Sync-UDElement -Id "currentAirwaveID" #-Properties @{value = $cache:dashinfo.$DashboardName.currentArubaID }


            
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
                        New-UDTextbox -FullWidth -id 'SettingsDb' -label 'Settings Db' -icon (New-UDIcon -Icon Database) -value $cache:dashinfo.$DashboardName.SettingsDb -placeholder '\\unc\path\to\shared.json' -Disabled
                    } -OnSubmit {

                        if (!(Test-Path function:priv_SaveSettingsFile)) { iex $cache:dashinfo.$DashboardName.settingsFunctionsSB.ToString() }

                        $cache:dashinfo.$DashboardName.settingsObj.ReportsDirectory = $EventData.ReportsDirectory
                        #$cache:dashinfo.$DashboardName.SettingsDb = $EventData.SettingsDb
                
                        priv_SaveSettingsFile -settingsFile $cache:dashinfo.$DashboardName.SettingsDb
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