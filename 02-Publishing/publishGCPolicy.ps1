# 1.1 This is an optional step if you want to publish the package to storage account
Publish-GuestConfigurationPackage -Path ./virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.zip `
                -ResourceGroupName azconf `
                -StorageAccountName azconfchaganti `
                -StorageContainerName policy | Select-Object -Property ContentUri

# 1.2 This publishes the policy definition to Azure Policy
Publish-GuestConfigurationPolicy -Path ./virtualMemoryShouldBe50GB/Policies

# 2.1 This is an optional step if you want to publish the package to storage account
Publish-GuestConfigurationPackage -Path ./TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.zip `
                -ResourceGroupName azconf `
                -StorageAccountName azconfchaganti `
                -StorageContainerName policy | Select-Object -Property ContentUri

# 2.2 This publishes the policy definition to Azure Policy
Publish-GuestConfigurationPolicy -Path ./TimezoneConfiguredAsDesired/Policies