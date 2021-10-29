$configName = 'virtualMemoryShouldBe50GB'
configuration $configName {
    Import-DscResource -ModuleName ComputerManagementDsc -Name VirtualMemory

    Node $configName {
        VirtualMemory $configName {
            Type        = 'CustomSize'
            Drive       = 'C'
            InitialSize = '51200'
            MaximumSize = '51200'
        }
    }
}

. $configName