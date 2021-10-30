# Requires PowerShell 7
Install-Module -Name GuestConfiguration -Force

# Get commands in Guest Configuration module
Get-Command -Module GuestConfiguration

# Install Guest Configuration Extension
Set-AzVMExtension -Publisher 'Microsoft.GuestConfiguration' `
        -Type 'ConfigurationforWindows' `
        -Name 'AzurePolicyforWindows' `
        -TypeHandlerVersion 1.0 `
        -ResourceGroupName 'azconf' `
        -Location 'eastus' `
        -VMName 'azconfwin02' `
        -EnableAutomaticUpgrade $true