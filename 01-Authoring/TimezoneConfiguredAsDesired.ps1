[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $true)]
    [String]
    $Timezone
)

$configName = 'TimezoneConfiguredAsDesired'
configuration $configName {
    Import-DscResource -ModuleName ComputerManagementDsc -Name Timezone

    Node $configName {
        Timezone $configName {
            IsSingleInstance = 'Yes'
            TimeZone         = $Timezone
        }
    }
}

. $configName