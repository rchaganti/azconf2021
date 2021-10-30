# 1.1 New Policy ID
$guid = (New-Guid).guid

New-GuestConfigurationPolicy `
-ContentUri "https://raw.githubusercontent.com/rchaganti/azconf2021/main/01-Authoring/TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.zip" `
-DisplayName "Timezone should be configured as desired" `
-Platform 'Windows' `
-Description 'Ensure that timezone is configured as specified' `
-Mode ApplyAndMonitor `
-PolicyId $guid `
-Path '.\TimezoneConfiguredAsDesired\Policies' `
-Verbose

# 1.2 New Policy ID
$guid = (New-Guid).guid

New-GuestConfigurationPolicy `
-ContentUri "https://raw.githubusercontent.com/rchaganti/azconf2021/main/01-Authoring/TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.zip" `
-DisplayName "Timezone should be configured as desired" `
-Platform 'Windows' `
-Description 'Ensure that timezone is configured as specified' `
-Mode ApplyAndMonitor `
-PolicyId $guid `
-Path '.\TimezoneConfiguredAsDesired\Policies' `
-Verbose