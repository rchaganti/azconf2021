# 1.1 New Policy ID
$guid = (New-Guid).guid

# Policy with No Parameters
New-GuestConfigurationPolicy `
-ContentUri "https://raw.githubusercontent.com/rchaganti/azconf2021/main/01-Authoring/virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.mof"
-DisplayName "Virtual memory should be set to at least 50GB" `
-Platform 'Windows' `
-Description 'Ensure the VM virtual memory is configured to be at least 50GB in the C drive' `
-Mode ApplyAndMonitor `
-PolicyId $guid `
-Path '.\virtualMemoryShouldBe50GB\Policies' `
-Verbose

# 1.2 New Policy ID
$guid = (New-Guid).guid

# Policy with Parameters
$policyParamInfo = @(
  @{
    Name = 'Timezone'                                              
    DisplayName = 'Timezone to configure.'
    Description = 'Timezone to configure.'
    ResourceType = 'Timezone'
    ResourceId = 'TimezoneConfiguredAsDesired'
    ResourcePropertyName = 'Timezone'                          
    DefaultValue = 'India Standard Time'
    AllowedValues = @('India Standard Time','Pacific Standard Time')
  }
)

New-GuestConfigurationPolicy `
-ContentUri "https://raw.githubusercontent.com/rchaganti/azconf2021/main/01-Authoring/TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.zip" `
-DisplayName "Timezone should be configured as desired" `
-Platform 'Windows' `
-Description 'Ensure that timezone is configured as specified' `
-Mode ApplyAndAutoCorrect `
-PolicyId $guid `
-Path '.\TimezoneConfiguredAsDesired\Policies' `
-Parameter $policyParamInfo `
-Verbose