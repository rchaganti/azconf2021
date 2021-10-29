New-GuestConfigurationPolicy `
-ContentUri "https://test.blob.core.windows.net/testazurepolicy/WindowsHardeningSample.zip?sp=r&st=2020-02-07T23:52:11Z&se=2020-02-29T07:52:11Z&spr=https&sv=2019-02-02&sr=b&sig=ILVs1Ik65%2BUrGTTTPdQDPoEYxvu1kT8%2F1K%2FvwXQcjE0%3D" `
-DisplayName "Windows Server 2016 Baseline" `
-Path '.\WindowsHardeningSample\Artifacts' `
-Platform 'Windows' `
-Description 'Ensure VMs running Windows Server 2016 OS meet WTW base hardening requirements' `
-Verbose