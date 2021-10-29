# New Policy ID
$guid = (New-Guid).guid

New-GuestConfigurationPolicy `
-ContentUri "https://raw.githubusercontent.com/rchaganti/azconf2021/main/01-Authoring/virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.zip" `
-DisplayName "Virtual memory should be set to at least 50GB" `
-Platform 'Windows' `
-Description 'Ensure the VM virtual memory is configured to be at least 50GB in the C drive' `
-Mode ApplyAndMonitor `
-PolicyId $guid `
-Path '.\virtualMemoryShouldBe50GB\Policies' `
-Verbose