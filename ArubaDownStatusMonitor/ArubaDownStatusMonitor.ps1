$title = 'ArubaDown Status Monitor'

New-UDApp -Title $title -Pages @(
    Get-UDPage -Name 'Home'
    Get-UDPage -Name 'Settings'

)

#region: dashboard onstart boilerplate

$dashPath = $PSScriptRoot
$DashboardName = split-path $dashPath -Leaf

if (!$cache:dashinfo) { $cache:dashinfo = @{} }
if (!$cache:dashinfo.$DashboardName) { $cache:dashinfo.$DashboardName = @{} }
if (!$cache:dashinfo.$DashboardName.dashPath) { $cache:dashinfo.$DashboardName.dashPath = $dashPath }

#endregion