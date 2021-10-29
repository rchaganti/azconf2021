# This is an optional step if you want to publish the package to storage account
Publish-GuestConfigurationPackage -Path ./virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.zip `
                -ResourceGroupName azconf `
                -StorageAccountName azconfchaganti `
                -StorageContainerName policy | Select-Object -Property ContentUri

# This publishes the policy definition to Azure Policy
Publish-GuestConfigurationPolicy -Path ./virtualMemoryShouldBe50GB/Policies