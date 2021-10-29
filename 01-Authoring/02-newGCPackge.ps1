# 1.1 Create a package that will only audit compliance
New-GuestConfigurationPackage `
  -Name 'virtualMemoryShouldBe50GB' `
  -Configuration './virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.mof' `
  -Type Audit `
  -Force

# 1.2 Validate GC Package
Get-GuestConfigurationPackageComplianceStatus -Path './virtualMemoryShouldBe50GB/virtualMemoryShouldBe50GB.zip'

# 2.1 Create a package that will only audit compliance
New-GuestConfigurationPackage `
  -Name 'TimezoneConfiguredAsDesired' `
  -Configuration './TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.mof' `
  -Type AuditAndSet `
  -Force

# 2.2 Validate GC Package
Get-GuestConfigurationPackageComplianceStatus -Path './TimezoneConfiguredAsDesired/TimezoneConfiguredAsDesired.zip'