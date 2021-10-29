# Create a package that will only audit compliance
New-GuestConfigurationPackage `
  -Name 'virtualMemoryShouldBe50GB' `
  -Configuration './virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.mof' `
  -Type Audit `
  -Force