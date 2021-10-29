using namespace System.IO.Compression.ZipFile
#Region './prefix.ps1' 0
Set-StrictMode -Version latest
$ErrorActionPreference = 'Stop'

Import-Module $PSScriptRoot/Modules/GuestConfigPath -Force
Import-Module $PSScriptRoot/Modules/DscOperations -Force
Import-Module $PSScriptRoot/Modules/GuestConfigurationPolicy -Force
Import-LocalizedData -BaseDirectory $PSScriptRoot -FileName GuestConfiguration.psd1 -BindingVariable GuestConfigurationManifest

if ($IsLinux -and (
    $PSVersionTable.PSVersion.Major -lt 7 -or
    ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 2) -or
    ($PSVersionTable.PSVersion.Major -eq 7 -and ($PSVersionTable.PSVersion.PreReleaseLabel -and [int](($PSVersionTable.PSVersion.PreReleaseLabel -split '\.')[1]) -lt 6))
    ))
{
    throw 'The Linux agent requires at least PowerShell v7.2.preview.6 to support the DSC subsystem.'
}

$currentCulture = [System.Globalization.CultureInfo]::CurrentCulture
if (($currentCulture.Name -eq 'en-US-POSIX') -and ($(Get-OSPlatform) -eq 'Linux'))
{
    Write-Warning "'$($currentCulture.Name)' Culture is not supported, changing it to 'en-US'"
    # Set Culture info to en-US
    [System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::new('en-US')
    [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('en-US')
}

#inject version info to GuestConfigPath.psm1
InitReleaseVersionInfo $GuestConfigurationManifest.moduleVersion
#EndRegion './prefix.ps1' 29
#Region './Enum/AssignmentType.ps1' 0
enum AssignmentType
{
    ApplyAndAutoCorrect
    ApplyAndMonitor
    Audit
}
#EndRegion './Enum/AssignmentType.ps1' 7
#Region './Enum/PackageType.ps1' 0
enum PackageType
{
    Audit
    AuditAndSet
}
#EndRegion './Enum/PackageType.ps1' 6
#Region './Private/Compress-ArchiveByDirectory.ps1' 0
#using namespace System.IO.Compression.ZipFile

<#
    .SYNOPSIS
        Create an Zip file from a Directory, including hidden files and folders.

    .DESCRIPTION
        The Compress-Archive is not copying hidden files and Directory by default,
        and it can be tricky to make it work without losing the Directory structure.
        However the `[System.IO.Compression.ZipFile]::CreateFromDirectory()` method
        makes it possible, and this function is a wrapper for it.
        The reason for creating a wrapper is to simplify testing via mocking.

    .PARAMETER Path
        Path of the File or Directory to compress.

    .PARAMETER DestinationPath
        Destination file to Zip the Directory into.

    .PARAMETER CompressionLevel
        Compression level between Fastest, Optimal, and NoCompression.

    .PARAMETER IncludeBaseDirectory
        Whether you want the zip to include the Directory and its content in the zip,
        or if you only want the content of the Directory to be at the zip's root (default).

    .PARAMETER Force
        Delete the destination file if it already exists.

    .EXAMPLE
        PS C:\> Compress-ArchiveByDirectory -Path C:\MyDir -DestinationPath C:\MyDir.zip -CompressionLevel Fastest -IncludeBaseDirectory -Force

#>
function Compress-ArchiveByDirectory
{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DestinationPath,

        [Parameter()]
        [System.IO.Compression.CompressionLevel]
        $CompressionLevel = [System.IO.Compression.CompressionLevel]::Fastest,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeBaseDirectory,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    if (-not  (Split-Path -IsAbsolute -Path $DestinationPath))
    {
        $DestinationPath = Join-Path -Path (Get-Location -PSProvider fileSystem) -ChildPath $DestinationPath
    }

    if ($PSBoundParameters.ContainsKey('Force') -and $true -eq $PSBoundParameters['Force'])
    {
        if ((Test-Path -Path $DestinationPath) -and $PSCmdlet.ShouldProcess("Deleting Zip file '$DestinationPath'.", $DestinationPath, 'Remove-Item -Force'))
        {
            Remove-Item -Force $DestinationPath -ErrorAction Stop
        }
    }

    if ($PSCmdlet.ShouldProcess("Zipping '$Path' to '$DestinationPath' with compression level '$CompressionLevel', includig base dir: '$($IncludeBaseDirectory.ToBool())'.", $Path, 'ZipFile'))
    {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($Path, $DestinationPath, $CompressionLevel, $IncludeBaseDirectory.ToBool())
    }
}
#EndRegion './Private/Compress-ArchiveByDirectory.ps1' 81
#Region './Private/Get-GuestConfigurationPackageFromUri.ps1' 0
function Get-GuestConfigurationPackageFromUri
{
    [CmdletBinding()]
    [OutputType([System.Io.FileInfo])]
    param
    (
        [Parameter()]
        [Uri]
        [ValidateScript({([Uri]$_).Scheme -match '^http'})]
        [Alias('Url')]
        $Uri
    )

    # Abstracting this in another function as we may want to support Proxy later.
    $tempFileName = [io.path]::GetTempFileName()
    $null = [System.Net.WebClient]::new().DownloadFile($Uri, $tempFileName)

    # The zip can be PackageName_0.2.3.zip, so we really need to look at the MOF to find its name.
    $packageName = Get-GuestConfigurationPackageNameFromZip -Path $tempFileName

    Move-Item -Path $tempFileName -Destination ('{0}.zip' -f $packageName) -Force -PassThru
}
#EndRegion './Private/Get-GuestConfigurationPackageFromUri.ps1' 23
#Region './Private/Get-GuestConfigurationPackageMetaConfig.ps1' 0
function Get-GuestConfigurationPackageMetaConfig
{
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $packageName = Get-GuestConfigurationPackageName -Path $Path
    $metadataFileName = '{0}.metaconfig.json' -f $packageName
    $metadataFile = Join-Path -Path $Path -ChildPath $metadataFileName

    if (Test-Path -Path $metadataFile)
    {
        Write-Debug -Message "Loading metadata from meta config file '$metadataFile'."
        $metadata = Get-Content -raw -Path $metadataFile | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    else
    {
        $metadata = @{}
    }

    #region Extra meta file until Agent supports one unique metadata file
    $extraMetadataFileName = 'extra.{0}' -f $metadataFileName
    $extraMetadataFile = Join-Path -Path $Path -ChildPath $extraMetadataFileName

    if (Test-Path -Path $extraMetadataFile)
    {
        Write-Debug -Message "Loading extra metadata from extra meta file '$extraMetadataFile'."
        $extraMetadata = Get-Content -raw -Path $extraMetadataFile | ConvertFrom-Json -AsHashtable -ErrorAction Stop

        foreach ($extraKey in $extraMetadata.keys)
        {
            if (-not $metadata.ContainsKey($extraKey))
            {
                $metadata[$extraKey] = $extraMetadata[$extraKey]
            }
            else
            {
                Write-Verbose -Message "The metadata '$extraKey' is already defined in '$metadataFile'."
            }
        }
    }
    #endregion

    return $metadata
}
#EndRegion './Private/Get-GuestConfigurationPackageMetaConfig.ps1' 51
#Region './Private/Get-GuestConfigurationPackageMetadataFromZip.ps1' 0
function Get-GuestConfigurationPackageMetadataFromZip
{
    [CmdletBinding()]
    [OutputType([PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Io.FileInfo]
        $Path
    )

    $Path = [System.IO.Path]::GetFullPath($Path) # Get Absolute path as .Net methods don't like relative paths.

    try
    {
        $tempFolderPackage = Join-Path -Path ([io.path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        Expand-Archive -LiteralPath $Path -DestinationPath $tempFolderPackage -Force
        Get-GuestConfigurationPackageMetaConfig -Path $tempFolderPackage
    }
    finally
    {
        # Remove the temporarily extracted package
        Remove-Item -Force -Recurse $tempFolderPackage -ErrorAction SilentlyContinue
    }
}
#EndRegion './Private/Get-GuestConfigurationPackageMetadataFromZip.ps1' 26
#Region './Private/Get-GuestConfigurationPackageName.ps1' 0
function Get-GuestConfigurationPackageName
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Io.FileInfo]
        $Path
    )

    $Path = [System.IO.Path]::GetFullPath($Path) # Get Absolute path as .Net method don't like relative paths.
    # Make sure we only get the MOF which is at the root of the package
    $mofFile = @() + (Get-ChildItem -Path (Join-Path -Path $Path -ChildPath *.mof) -File -ErrorAction Stop)

    if ($mofFile.Count -ne 1)
    {
        throw "Invalid GuestConfiguration Package at '$Path'. Found $($mofFile.Count) mof files."
        return
    }
    else
    {
        Write-Debug -Message "Found the MOF '$($moffile)' in $Path."
    }

    return ([System.Io.Path]::GetFileNameWithoutExtension($mofFile[0]))
}
#EndRegion './Private/Get-GuestConfigurationPackageName.ps1' 28
#Region './Private/Get-GuestConfigurationPackageNameFromZip.ps1' 0
function Get-GuestConfigurationPackageNameFromZip
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [System.Io.FileInfo]
        $Path
    )

    $Path = [System.IO.Path]::GetFullPath($Path) # Get Absolute path as .Net method don't like relative paths.

    try
    {
        $zipRead = [IO.Compression.ZipFile]::OpenRead($Path)
        # Make sure we only get the MOF which is at the root of the package
        $mofFile = @() + $zipRead.Entries.FullName.Where({((Split-Path -Leaf -Path $_) -eq $_) -and $_ -match '\.mof$'})
    }
    finally
    {
        # Close the zip so we can move it.
        $zipRead.Dispose()
    }

    if ($mofFile.count -ne 1)
    {
        throw "Invalid policy package, failed to find unique dsc document in policy package downloaded from '$Uri'."
    }

    return ([System.Io.Path]::GetFileNameWithoutExtension($mofFile[0]))
}
#EndRegion './Private/Get-GuestConfigurationPackageNameFromZip.ps1' 32
#Region './Private/Update-GuestConfigurationPackageMetaconfig.ps1' 0
function Update-GuestConfigurationPackageMetaconfig
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $MetaConfigPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Value
    )

    $metadataFile = $MetaConfigPath

    #region Write extra metadata on different file until the GC Agents supports it
    if ($Key -notin @('debugMode','ConfigurationModeFrequencyMins','configurationMode'))
    {
        $fileName = Split-Path -Path $MetadataFile -Leaf
        $filePath = Split-Path -Path $MetadataFile -Parent
        $metadataFileName = 'extra.{0}' -f $fileName

        $metadataFile = Join-Path -Path $filePath -ChildPath $metadataFileName
    }
    #endregion

    Write-Debug -Message "Updating the file '$metadataFile' with key $Key = '$Value'."

    if (Test-Path -Path $metadataFile)
    {
        $metaConfigObject = Get-Content -Raw -Path $metadataFile | ConvertFrom-Json -AsHashtable
        $metaConfigObject[$Key] = $Value
        $metaConfigObject | ConvertTo-Json | Out-File -Path $metadataFile -Encoding ascii -Force
    }
    else
    {
        @{
            $Key = $Value
        } | ConvertTo-Json | Out-File -Path $metadataFile -Encoding ascii -Force
    }
}
#EndRegion './Private/Update-GuestConfigurationPackageMetaconfig.ps1' 47
#Region './Public/Get-GuestConfigurationPackageComplianceStatus.ps1' 0
function Get-GuestConfigurationPackageComplianceStatus
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.String]
        $Path,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Hashtable[]]
        $Parameter = @()
    )

    begin
    {
        # Determine if verbose is enabled to pass down to other functions
        $verbose = ($PSBoundParameters.ContainsKey("Verbose") -and ($PSBoundParameters["Verbose"] -eq $true))
        $systemPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Process")
        $gcBinPath = Get-GuestConfigBinaryPath
        $guestConfigurationPolicyPath = Get-GuestConfigPolicyPath

    }

    process
    {
        try
        {
            if ($PSBoundParameters.ContainsKey('Force') -and $Force)
            {
                $withForce = $true
            }
            else
            {
                $withForce = $false
            }

            $packagePath = Install-GuestConfigurationPackage -Path $Path -Force:$withForce

            Write-Debug -Message "Looking into Package '$PackagePath' for MOF document."

            $packageName = Get-GuestConfigurationPackageName -Path $PackagePath

            # Confirm mof exists
            $packageMof = Join-Path -Path $packagePath -ChildPath "$packageName.mof"
            $dscDocument = Get-Item -Path $packageMof -ErrorAction 'SilentlyContinue'

            if (-not $dscDocument)
            {
                throw "Invalid Guest Configuration package, failed to find dsc document at '$packageMof' path."
            }

            # update configuration parameters
            if ($Parameter.Count -gt 0)
            {
                Update-MofDocumentParameters -Path $dscDocument.FullName -Parameter $Parameter
            }

            # Publish policy package
            Publish-DscConfiguration -ConfigurationName $packageName -Path $PackagePath -Verbose:$verbose

            # Set LCM settings to force load powershell module.
            $metaConfigPath = Join-Path -Path $PackagePath -ChildPath "$packageName.metaconfig.json"
            Update-GuestConfigurationPackageMetaconfig -metaConfigPath $metaConfigPath -Key 'debugMode' -Value 'ForceModuleImport'

            Set-DscLocalConfigurationManager -ConfigurationName $packageName -Path $PackagePath -Verbose:$verbose


            # Clear Inspec profiles
            Remove-Item -Path $(Get-InspecProfilePath) -Recurse -Force -ErrorAction SilentlyContinue

            $getResult = @()
            $getResult = $getResult + (Get-DscConfiguration -ConfigurationName $packageName -Verbose:$verbose)
            return $getResult
        }
        finally
        {
            $env:PSModulePath = $systemPSModulePath
        }
    }
}
#EndRegion './Public/Get-GuestConfigurationPackageComplianceStatus.ps1' 83
#Region './Public/Install-GuestConfigurationAgent.ps1' 0
function Install-GuestConfigurationAgent
{
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    # Unzip Guest Configuration binaries
    $gcBinPath = Get-GuestConfigBinaryPath
    $gcBinRootPath = Get-GuestConfigBinaryRootPath
    $OsPlatform = Get-OSPlatform
    if ($PSBoundParameters.ContainsKey('Force') -and $PSBoundParameters['Force'])
    {
        $withForce = $true
    }
    else
    {
        $withForce = $false
    }

    if ((-not (Test-Path -Path $gcBinPath)) -or $withForce)
    {
        # Clean the bin folder
        Write-Verbose -Message "Removing existing installation from '$gcBinRootPath'."
        Remove-Item -Path $gcBinRootPath'\*' -Recurse -Force -ErrorAction SilentlyContinue
        $zippedBinaryPath = Join-Path -Path $(Get-GuestConfigurationModulePath) -ChildPath 'bin'

        if ($OsPlatform -eq 'Windows')
        {
            $zippedBinaryPath = Join-Path -Path $zippedBinaryPath -ChildPath 'DSC_Windows.zip'
        }
        else
        {
            # Linux zip package contains an additional DSC folder
            # Remove DSC folder from binary path to avoid two nested DSC folders.
            $null = New-Item -ItemType Directory -Force -Path $gcBinPath
            $gcBinPath = (Get-Item -Path $gcBinPath).Parent.FullName
            $zippedBinaryPath = Join-Path $zippedBinaryPath 'DSC_Linux.zip'
        }

        Write-Verbose -Message "Extracting '$zippedBinaryPath' to '$gcBinPath'."
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zippedBinaryPath, $gcBinPath)

        if ($OsPlatform -ne 'Windows')
        {
            # Fix for “LTTng-UST: Error (-17) while registering tracepoint probe. Duplicate registration of tracepoint probes having the same name is not allowed.”
            Get-ChildItem -Path $gcBinPath -Filter libcoreclrtraceptprovider.so -Recurse | ForEach-Object {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }

            Get-ChildItem -Path $gcBinPath -Filter *.sh -Recurse | ForEach-Object -Process {
                chmod @('+x', $_.FullName)
            }
        }

	# Save config file
    $gcConfigPath = Join-Path (Get-GuestConfigBinaryPath) 'gc.config'
    '{ "SaveLogsInJsonFormat": true, "DoNotSendReport": true}' | Out-File -Path $gcConfigPath -Encoding ascii -Force

    if ($OsPlatform -ne 'Windows')
    {
        # Give root user permission to execute gc_worker
        chmod 700 (Get-GuestConfigWorkerBinaryPath)
    }
}
    else
    {
        Write-Verbose -Message "Guest Configuration Agent binaries already installed at '$gcBinPath', skipping."
    }
}
#EndRegion './Public/Install-GuestConfigurationAgent.ps1' 75
#Region './Public/Install-GuestConfigurationPackage.ps1' 0
<#
    .SYNOPSIS
        Installs a Guest Configuration policy package.

    .Parameter Package
        Path or Uri of the Guest Configuration package zip.

    .Parameter Force
        Force installing over an existing package, even if it already exists.

    .Example
        Install-GuestConfigurationPackage -Path ./custom_policy/WindowsTLS.zip

        Install-GuestConfigurationPackage -Path ./custom_policy/AuditWindowsService.zip -Force

    .OUTPUTS
        The path to the installed Guest Configuration package.
#>

function Install-GuestConfigurationPackage
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    $osPlatform = Get-OSPlatform

    if ($osPlatform -eq 'MacOS')
    {
        throw 'The Install-GuestConfigurationPackage cmdlet is not supported on MacOS'
    }


    $verbose = $VerbosePreference -ne 'SilentlyContinue' -or ($PSBoundParameters.ContainsKey('Verbose') -and ($PSBoundParameters['Verbose'] -eq $true))
    $systemPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
    $guestConfigurationPolicyPath = Get-GuestConfigPolicyPath

    try
    {
        # Unzip Guest Configuration binaries if missing
        Install-GuestConfigurationAgent -verbose:$verbose

        # Resolve the zip (to temp folder if URI)
        if (($Path -as [uri]).Scheme -match '^http')
        {
            # Get the package from URI to a temp folder
            $PackageZipPath = (Get-GuestConfigurationPackageFromUri -Uri $Path -Verbose:$verbose).ToString()
        }
        elseif ((Test-Path -PathType 'Leaf' -Path $Path) -and $Path -match '\.zip$')
        {
            $PackageZipPath = (Resolve-Path -Path $Path).ToString()
        }
        else
        {
            # The $Path parameter is not a valid path or URL
            throw "'$Path' is not a valid path to the package. Please provide the path to the Zip or the URL to download the package from."
        }

        Write-Debug -Message "Getting package name from '$PackageZipPath'."
        $packageName = Get-GuestConfigurationPackageNameFromZip -Path $PackageZipPath
        $packageZipMetadata = Get-GuestConfigurationPackageMetadataFromZip -Path $PackageZipPath -Verbose:$verbose
        $installedPackagePath = Join-Path -Path $guestConfigurationPolicyPath -ChildPath $packageName
        $isPackageAlreadyInstalled = $false

        if (Test-Path -Path $installedPackagePath)
        {
            Write-Debug -Message "The Package '$PackageName' exists at '$installedPackagePath'. Checking version..."
            $installedPackageMetadata = Get-GuestConfigurationPackageMetaConfig -Path $installedPackagePath -Verbose:$verbose

            # None of the packages are versioned or the versions match, we're good
            if (-not ($installedPackageMetadata.ContainsKey('Version') -or $packageZipMetadata.Contains('Version')) -or
                ($installedPackageMetadata.ContainsKey('Version') -ne $packageZipMetadata.Contains('Version')) -or # to avoid next statement
                $installedPackageMetadata.Version -eq $packageZipMetadata.Version)
            {
                $isPackageAlreadyInstalled = $true
                Write-Debug -Message ("Package '{0}{1}' is installed." -f $PackageName,($packageZipMetadata.Contains('Version') ? "_$($packageZipMetadata['Version'])" : ''))
            }
            else
            {
                Write-Verbose -Message "Package '$packageName' was found at version '$($installedPackageMetadata.Version)' but we're expecting '$($packageZipMetadata.Version)'."
            }
        }

        if ($PSBoundParameters.ContainsKey('Force') -and $PSBoundParameters['Force'])
        {
            $withForce = $true
        }
        else
        {
            $withForce = $false
        }

        if ((-not $isPackageAlreadyInstalled) -or $withForce)
        {
            Write-Debug -Message "Removing existing package at '$installedPackagePath'."
            Remove-Item -Path $installedPackagePath -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -ItemType Directory -Force -Path $installedPackagePath
            # Unzip policy package
            Write-Verbose -Message "Unzipping the Guest Configuration Package to '$installedPackagePath'."
            Expand-Archive -LiteralPath $PackageZipPath -DestinationPath $installedPackagePath -ErrorAction Stop -Force
        }
        else
        {
            Write-Verbose -Message "Package is already installed at '$installedPackagePath', skipping install."
        }

        # Clear Inspec profiles
        Remove-Item -Path (Get-InspecProfilePath) -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally
    {
        $env:PSModulePath = $systemPSModulePath

        # If we downloaded the Zip file from URI to temp folder, do cleanup
        if (($Path -as [uri]).Scheme -match '^http')
        {
            Write-Debug -Message "Removing the Package zip at '$PackageZipPath' that was downloaded from URI."
            Remove-Item -Force -ErrorAction SilentlyContinue -Path $PackageZipPath
        }
    }

    return $installedPackagePath
}
#EndRegion './Public/Install-GuestConfigurationPackage.ps1' 134
#Region './Public/New-GuestConfigurationFile.ps1' 0

<#
    .SYNOPSIS
        Automatically generate a MOF file based on
        files discovered in a folder path

        This command is optional and is intended to
        reduce the number of steps needed when
        using other language abstractions such as Pester

        When creating packages from compiled DSC
        configurations, you do not need to run this command

    .Parameter Source
        Location of the folder containing content

    .Parameter Path
        Location of the folder containing content

    .Parameter Format
        Format of the files (currently only Pester is supported)

    .Parameter Force
        When specified, will overwrite the destination file if it already exists

    .Example
        New-GuestConfigurationFile -Path ./Scripts

    .OUTPUTS
        Return the path of the generated configuration MOF file
#>

function New-GuestConfigurationFile
{
    [CmdletBinding()]
    [Experimental("GuestConfiguration.Pester", "Show")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter(Position = 1, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Source,

        [Parameter(Position = 2, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(Position = 3, ValueFromPipelineByPropertyName = $true)]
        [System.String]
        $Format = 'Pester',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    $return = [PSCustomObject]@{
        Name = ''
        Configuration = ''
    }

    if ('Pester' -eq $Format)
    {
        Write-Warning -Message 'Guest Configuration: Pester content is an expiremental feature and not officially supported'
        if ([ExperimentalFeature]::IsEnabled("GuestConfiguration.Pester"))
        {
            $ConfigMOF = New-MofFileforPester -Name $Name -PesterScriptsPath $Source -Path $Path -Force:$Force
            $return.Name = $Name
            $return.Configuration = $ConfigMOF.Path
        }
        else
        {
            throw 'Before you can use Pester content, you must enable the experimental feature in PowerShell.'
        }
    }

    return $return
}
#EndRegion './Public/New-GuestConfigurationFile.ps1' 86
#Region './Public/New-GuestConfigurationPackage.ps1' 0

<#
    .SYNOPSIS
        Creates a Guest Configuration policy package.

    .Parameter Name
        Guest Configuration package name.

    .Parameter Version
        Guest Configuration package Version (SemVer).

    .Parameter Configuration
        Compiled DSC configuration document full path.

    .Parameter Path
        Output folder path.
        This is an optional parameter. If not specified, the package will be created in the current directory.

    .Parameter ChefInspecProfilePath
        Chef profile path, supported only on Linux.

    .Parameter Type
        Specifies whether or not package will support AuditAndSet or only Audit. Set to Audit by default.

    .Parameter Force
        Overwrite the package files if already present.

    .Example
        New-GuestConfigurationPackage -Name WindowsTLS -Configuration ./custom_policy/WindowsTLS/localhost.mof -Path ./git/repository/release/policy/WindowsTLS

    .OUTPUTS
        Return name and path of the new Guest Configuration Policy package.
#>

function New-GuestConfigurationPackage
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = 'Configuration', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Configuration,

        [Parameter(Position = 2, ParameterSetName = 'Configuration', ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [SemVer]
        $Version,

        [Parameter(ParameterSetName = 'Configuration')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ChefInspecProfilePath,

        [Parameter(ParameterSetName = 'Configuration')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $FilesToInclude,

        [Parameter()]
        [System.String]
        $Path = '.',

        [Parameter()]
        [PackageType]
        $Type = 'Audit',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    if (-not (Get-Variable -Name Type -ErrorAction SilentlyContinue))
    {
        $Type = 'Audit'
    }

    $verbose = ($PSBoundParameters.ContainsKey("Verbose") -and ($PSBoundParameters["Verbose"] -eq $true))
    $stagingPackagePath = Join-Path -Path (Join-Path -Path $Path -ChildPath $Name) -ChildPath 'unzippedPackage'
    $unzippedPackageDirectory = New-Item -ItemType Directory -Force -Path $stagingPackagePath
    $Configuration = Resolve-Path -Path $Configuration

    if (-not (Test-Path -Path $Configuration -PathType Leaf))
    {
        throw "Invalid mof file path, please specify full file path for dsc configuration in -Configuration parameter."
    }

    Write-Verbose -Message "Creating Guest Configuration package in temporary directory '$unzippedPackageDirectory'"

    # Verify that only supported resources are used in DSC configuration.
    Test-GuestConfigurationMofResourceDependencies -Path $Configuration -Verbose:$verbose

    # Save DSC configuration to the temporary package path.
    $configMOFPath = Join-Path -Path $unzippedPackageDirectory -ChildPath "$Name.mof"
    Save-GuestConfigurationMofDocument -Name $Name -SourcePath $Configuration -DestinationPath $configMOFPath -Verbose:$verbose

    # Copy DSC resources
    Copy-DscResources -MofDocumentPath $Configuration -Destination $unzippedPackageDirectory -Verbose:$verbose -Force:$Force

    # Modify metaconfig file
    $metaConfigPath = Join-Path -Path $unzippedPackageDirectory -ChildPath "$Name.metaconfig.json"
    Update-GuestConfigurationPackageMetaconfig -metaConfigPath $metaConfigPath -Key 'Type' -Value $Type.ToString()

    if ($PSBoundParameters.ContainsKey('Version'))
    {
        Update-GuestConfigurationPackageMetaconfig -MetaConfigPath $metaConfigPath -key 'Version' -Value $Version.ToString()
    }

    if (-not [string]::IsNullOrEmpty($ChefInspecProfilePath))
    {
        # Copy Chef resource and profiles.
        Copy-ChefInspecDependencies -PackagePath $unzippedPackageDirectory -Configuration $Configuration -ChefInspecProfilePath $ChefInspecProfilePath
    }

    # Copy FilesToInclude
    if (-not [string]::IsNullOrEmpty($FilesToInclude))
    {
        $modulePath = Join-Path $unzippedPackageDirectory 'Modules'
        if (Test-Path $FilesToInclude -PathType Leaf)
        {
            Copy-Item -Path $FilesToInclude -Destination $modulePath  -Force:$Force
        }
        else
        {
            $filesToIncludeFolderName = Get-Item -Path $FilesToInclude
            $FilesToIncludePath = Join-Path -Path $modulePath -ChildPath $filesToIncludeFolderName.Name
            Copy-Item -Path $FilesToInclude -Destination $FilesToIncludePath -Recurse -Force:$Force
        }
    }

    # Create Guest Configuration Package.
    $packagePath = Join-Path -Path $Path -ChildPath $Name
    $null = New-Item -ItemType Directory -Force -Path $packagePath
    $packagePath = Resolve-Path -Path $packagePath
    $packageFilePath = join-path -Path $packagePath -ChildPath "$Name.zip"
    if (Test-Path -Path $packageFilePath)
    {
        Remove-Item -Path $packageFilePath -Force -ErrorAction SilentlyContinue
    }

    Write-Verbose -Message "Creating Guest Configuration package : $packageFilePath."
    Compress-ArchiveByDirectory -Path $unzippedPackageDirectory -DestinationPath $packageFilePath -Force:$Force

    [pscustomobject]@{
        PSTypeName = 'GuestConfiguration.Package'
        Name = $Name
        Path = $packageFilePath
    }
}
#EndRegion './Public/New-GuestConfigurationPackage.ps1' 156
#Region './Public/New-GuestConfigurationPolicy.ps1' 0

<#
    .SYNOPSIS
        Creates Audit, DeployIfNotExists and Initiative policy definitions on specified Destination Path.

    .Parameter ContentUri
        Public http uri of Guest Configuration content package.

    .Parameter DisplayName
        Policy display name.

    .Parameter Description
        Policy description.

    .Parameter Parameter
        Policy parameters.

    .Parameter Version
        Policy version.

    .Parameter Path
        Destination path.

    .Parameter Platform
        Target platform (Windows/Linux) for Guest Configuration policy and content package.
        Windows is the default platform.

    .Parameter Mode
        Defines whether or not the policy is Audit or Deploy. Acceptable values: Audit, ApplyAndAutoCorrect, or ApplyAndMonitor. Audit is the default mode.

    .Parameter Tag
        The name and value of a tag used in Azure.

    .Example
        New-GuestConfigurationPolicy `
                                 -ContentUri https://github.com/azure/auditservice/release/AuditService.zip `
                                 -DisplayName 'Monitor Windows Service Policy.' `
                                 -Description 'Policy to monitor service on Windows machine.' `
                                 -Version 1.0.0.0
                                 -Path ./git/custom_policy
                                 -Tag @{Owner = 'WebTeam'}

        $PolicyParameterInfo = @(
            @{
                Name = 'ServiceName'                                       # Policy parameter name (mandatory)
                DisplayName = 'windows service name.'                      # Policy parameter display name (mandatory)
                Description = "Name of the windows service to be audited." # Policy parameter description (optional)
                ResourceType = "Service"                                   # dsc configuration resource type (mandatory)
                ResourceId = 'windowsService'                              # dsc configuration resource property name (mandatory)
                ResourcePropertyName = "Name"                              # dsc configuration resource property name (mandatory)
                DefaultValue = 'winrm'                                     # Policy parameter default value (optional)
                AllowedValues = @('wscsvc','WSearch','wcncsvc','winrm')    # Policy parameter allowed values (optional)
            })

            New-GuestConfigurationPolicy -ContentUri 'https://github.com/azure/auditservice/release/AuditService.zip' `
                                 -DisplayName 'Monitor Windows Service Policy.' `
                                 -Description 'Policy to monitor service on Windows machine.' `
                                 -Version 1.0.0.0
                                 -Path ./policyDefinitions `
                                 -Parameter $PolicyParameterInfo

    .OUTPUTS
        Return name and path of the Guest Configuration policy definitions.
#>

function New-GuestConfigurationPolicy
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Uri]
        $ContentUri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DisplayName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Description,

        [Parameter()]
        [System.Collections.Hashtable[]]
        $Parameter,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.Version]
        $Version = '1.0.0',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateSet('Windows', 'Linux')]
        [System.String]
        $Platform = 'Windows',

        [Parameter()]
        [AssignmentType]
        $Mode = 'Audit',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $PolicyId,

        [Parameter()]
        [System.Collections.Hashtable[]]
        $Tag
    )

    # This value must be static for AINE policies due to service configuration
    $Category = 'Guest Configuration'

    try
    {
        $verbose = ($PSBoundParameters.ContainsKey("Verbose") -and ($PSBoundParameters["Verbose"] -eq $true))
        $policyDefinitionsPath = $Path
        $unzippedPkgPath = Join-Path -Path $policyDefinitionsPath -ChildPath 'temp'
        $tempContentPackageFilePath = Join-Path -Path $policyDefinitionsPath -ChildPath 'temp.zip'

        # Update parameter info
        $ParameterInfo = Update-PolicyParameter -Parameter $Parameter

        $null = New-Item -ItemType Directory -Force -Path $policyDefinitionsPath

        # Check if ContentUri is a valid web URI
        if (-not ($null -ne $ContentUri.AbsoluteURI -and $ContentUri.Scheme -match '[http|https]'))
        {
            throw "Invalid ContentUri : $ContentUri. Please specify a valid http URI in -ContentUri parameter."
        }

        # Generate checksum hash for policy content.
        Invoke-WebRequest -Uri $ContentUri -OutFile $tempContentPackageFilePath
        $tempContentPackageFilePath = Resolve-Path $tempContentPackageFilePath
        $contentHash = (Get-FileHash $tempContentPackageFilePath -Algorithm SHA256).Hash
        Write-Verbose "SHA256 Hash for content '$ContentUri' : $contentHash."

        # Get the policy name from policy content.
        Remove-Item $unzippedPkgPath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $unzippedPkgPath | Out-Null
        $unzippedPkgPath = Resolve-Path $unzippedPkgPath
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempContentPackageFilePath, $unzippedPkgPath)

        $dscDocument = Get-ChildItem -Path $unzippedPkgPath -Filter *.mof -Exclude '*.schema.mof' -Depth 1
        if (-not $dscDocument)
        {
            throw "Invalid policy package, failed to find dsc document in policy package."
        }

        $policyName = [System.IO.Path]::GetFileNameWithoutExtension($dscDocument)

        $packageIsSigned = (($null -ne (Get-ChildItem -Path $unzippedPkgPath -Filter *.cat)) -or
            (($null -ne (Get-ChildItem -Path $unzippedPkgPath -Filter *.asc)) -and ($null -ne (Get-ChildItem -Path $unzippedPkgPath -Filter *.sha256sums))))

        # Determine if policy is AINE or DINE
        if ($Mode -eq "Audit")
        {
            $FileName = 'AuditIfNotExists.json'
        }
        else {
            $FileName = 'DeployIfNotExists.json'
        }

        $PolicyInfo = @{
            FileName                 = $FileName
            DisplayName              = $DisplayName
            Description              = $Description
            Platform                 = $Platform
            ConfigurationName        = $policyName
            ConfigurationVersion     = $Version
            ContentUri               = $ContentUri
            ContentHash              = $contentHash
            AssignmentType           = $Mode
            ReferenceId              = "Deploy_$policyName"
            ParameterInfo            = $ParameterInfo
            UseCertificateValidation = $packageIsSigned
            Category                 = $Category
            Guid                     = $PolicyId
            Tag                      = $Tag
        }

        $null = New-CustomGuestConfigPolicy -PolicyFolderPath $policyDefinitionsPath -PolicyInfo $PolicyInfo -Verbose:$verbose

        [pscustomobject]@{
            PSTypeName = 'GuestConfiguration.Policy'
            Name = $policyName
            Path = $Path
        }
    }
    finally
    {
        # Remove staging content package.
        Remove-Item -Path $tempContentPackageFilePath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $unzippedPkgPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
#EndRegion './Public/New-GuestConfigurationPolicy.ps1' 206
#Region './Public/Protect-GuestConfigurationPackage.ps1' 0

<#
    .SYNOPSIS
        Signs a Guest Configuration policy package using certificate on Windows and Gpg keys on Linux.

    .Parameter Path
        Full path of the Guest Configuration package.

    .Parameter Certificate
        'Code Signing' certificate to sign the package. This is only supported on Windows.

    .Parameter PrivateGpgKeyPath
        Private Gpg key path. This is only supported on Linux.

    .Parameter PublicGpgKeyPath
        Public Gpg key path. This is only supported on Linux.

    .Example
        $Cert = Get-ChildItem -Path Cert:/CurrentUser/AuthRoot -Recurse | Where-Object {($_.Thumbprint -eq "0563b8630d62d75abbc8ab1e4bdfb5a899b65d43") }
        Protect-GuestConfigurationPackage -Path ./custom_policy/WindowsTLS.zip -Certificate $Cert

    .OUTPUTS
        Return name and path of the signed Guest Configuration Policy package.
#>

function Protect-GuestConfigurationPackage
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "Certificate")]
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "GpgKeys")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, ParameterSetName = "Certificate")]
        [ValidateNotNullOrEmpty()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        [Parameter(Mandatory = $true, ParameterSetName = "GpgKeys")]
        [ValidateNotNullOrEmpty()]
        [string]
        $PrivateGpgKeyPath,

        [Parameter(Mandatory = $true, ParameterSetName = "GpgKeys")]
        [ValidateNotNullOrEmpty()]
        [string]
        $PublicGpgKeyPath
    )

    $Path = Resolve-Path $Path
    if (-not (Test-Path $Path -PathType Leaf))
    {
        throw 'Invalid Guest Configuration package path.'
    }

    try
    {
        $packageFileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $signedPackageFilePath = Join-Path (Get-ChildItem $Path).Directory "$($packageFileName)_signed.zip"
        $tempDir = Join-Path -Path (Get-ChildItem $Path).Directory -ChildPath 'temp'
        Remove-Item $signedPackageFilePath -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Force -Path $tempDir

        # Unzip policy package.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $tempDir)

        # Get policy name
        $dscDocument = Get-ChildItem -Path $tempDir -Filter *.mof
        if (-not $dscDocument)
        {
            throw "Invalid policy package, failed to find dsc document in policy package."
        }

        $policyName = [System.IO.Path]::GetFileNameWithoutExtension($dscDocument)

        $osPlatform = Get-OSPlatform
        if ($PSCmdlet.ParameterSetName -eq "Certificate")
        {
            if ($osPlatform -eq "Linux")
            {
                throw 'Certificate signing not supported on Linux.'
            }

            # Create catalog file
            $catalogFilePath = Join-Path -Path $tempDir -ChildPath "$policyName.cat"
            Remove-Item $catalogFilePath -Force -ErrorAction SilentlyContinue
            Write-Verbose "Creating catalog file : $catalogFilePath."
            New-FileCatalog -Path $tempDir -CatalogVersion 2.0 -CatalogFilePath $catalogFilePath | Out-Null

            # Sign catalog file
            Write-Verbose "Signing catalog file : $catalogFilePath."
            $CodeSignOutput = Set-AuthenticodeSignature -Certificate $Certificate -FilePath $catalogFilePath

            $Signature = Get-AuthenticodeSignature $catalogFilePath
            if ($null -ne $Signature.SignerCertificate)
            {
                if ($Signature.SignerCertificate.Thumbprint -ne $Certificate.Thumbprint)
                {
                    throw $CodeSignOutput.StatusMessage
                }
            }
            else
            {
                throw $CodeSignOutput.StatusMessage
            }
        }
        else
        {
            if ($osPlatform -eq "Windows")
            {
                throw 'Gpg signing not supported on Windows.'
            }

            $PrivateGpgKeyPath = Resolve-Path $PrivateGpgKeyPath
            $PublicGpgKeyPath = Resolve-Path $PublicGpgKeyPath
            $ascFilePath = Join-Path $tempDir "$policyName.asc"
            $hashFilePath = Join-Path $tempDir "$policyName.sha256sums"

            Remove-Item $ascFilePath -Force -ErrorAction SilentlyContinue
            Remove-Item $hashFilePath -Force -ErrorAction SilentlyContinue

            Write-Verbose "Creating file hash : $hashFilePath."
            Push-Location -Path $tempDir
            bash -c "find ./ -type f -print0 | xargs -0 sha256sum | grep -v sha256sums > $hashFilePath"
            Pop-Location

            Write-Verbose "Signing file hash : $hashFilePath."
            gpg --import $PrivateGpgKeyPath
            gpg --no-default-keyring --keyring $PublicGpgKeyPath --output $ascFilePath --armor --detach-sign $hashFilePath
        }

        # Zip the signed Guest Configuration package
        Write-Verbose "Creating signed Guest Configuration package : '$signedPackageFilePath'."
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $signedPackageFilePath)

        $result = [pscustomobject]@{
            Name = $policyName
            Path = $signedPackageFilePath
        }

        return $result
    }
    finally
    {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
#EndRegion './Public/Protect-GuestConfigurationPackage.ps1' 151
#Region './Public/Publish-GuestConfigurationPackage.ps1' 0

<#
    .SYNOPSIS
        Publish a Guest Configuration policy package to Azure blob storage.
        The goal is to simplify the number of steps by scoping to a specific
        task.

        Generates a SAS token with a 3-year lifespan, to mitigate the risk
        of a malicious person discovering the published content.

        Requires a resource group, storage account, and container
        to be pre-staged. For details on how to pre-stage these things see the
        documentation for the Az Storage cmdlets.
        https://docs.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-powershell.

    .Parameter Path
        Location of the .zip file containing the Guest Configuration artifacts

    .Parameter ResourceGroupName
        The Azure resource group for the storage account

    .Parameter StorageAccountName
        The name of the storage account for where the package will be published
        Storage account names must be globally unique

    .Parameter StorageContainerName
        Name of the storage container in Azure Storage account (default: "guestconfiguration")

    .Example
        Publish-GuestConfigurationPackage -Path ./package.zip -ResourceGroupName 'resourcegroup' -StorageAccountName 'sa12345'

    .OUTPUTS
        Return a publicly accessible URI containing a SAS token with a 3-year expiration.
#>

function Publish-GuestConfigurationPackage
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ResourceGroupName,

        [Parameter(Position = 2, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StorageAccountName,

        [Parameter()]
        [System.String]
        $StorageContainerName = 'guestconfiguration',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    # Get Storage Context
    $Context = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName |
        ForEach-Object { $_.Context }

    # Blob name from file name
    $BlobName = (Get-Item -Path $Path -ErrorAction Stop).Name

    $setAzStorageBlobContentParams = @{
        Context   = $Context
        Container = $StorageContainerName
        Blob      = $BlobName
        File      = $Path
    }

    if ($true -eq $Force)
    {
        $setAzStorageBlobContentParams.Add('Force', $true)
    }

    # Upload file
    $null = Set-AzStorageBlobContent @setAzStorageBlobContentParams

    # Get url with SAS token
    # THREE YEAR EXPIRATION
    $StartTime = Get-Date

    $newAzStorageBlobSASTokenParams = @{
        Context    = $Context
        Container  = $StorageContainerName
        Blob       = $BlobName
        StartTime  = $StartTime
        ExpiryTime = $StartTime.AddYears('3')
        Permission = 'rl'
        FullUri    = $true
    }

    $SAS = New-AzStorageBlobSASToken @newAzStorageBlobSASTokenParams

    # Output
    return [PSCustomObject]@{
        ContentUri = $SAS
    }
}
#EndRegion './Public/Publish-GuestConfigurationPackage.ps1' 107
#Region './Public/Publish-GuestConfigurationPolicy.ps1' 0

<#
    .SYNOPSIS
        Publishes the Guest Configuration policy in Azure Policy Center.

    .Parameter Path
        Guest Configuration policy path.

    .Example
        Publish-GuestConfigurationPolicy -Path ./git/custom_policy
#>

function Publish-GuestConfigurationPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $ManagementGroupName
    )

    $rmContext = Get-AzContext
    Write-Verbose -Message "Publishing Guest Configuration policy using '$($rmContext.Name)' AzContext."

    # Publish policies
    $currentFiles = @(Get-ChildItem $Path | Where-Object -FilterScript {
        $_.name -like "DeployIfNotExists.json" -or $_.name -like "AuditIfNotExists.json"
    })

    if ($currentFiles.Count -eq 0)
    {
        throw "No valid AuditIfNotExists.json or DeployIfNotExists.json files found at $Path"
    }
    elseif ($currentFiles.Count -gt 1)
    {
        throw "More than one valid json found at $Path"
    }

    $policyFile = $currentFiles[0]
    $jsonDefinition = Get-Content -Path $policyFile | ConvertFrom-Json | ForEach-Object { $_ }
    $definitionContent = $jsonDefinition.Properties

    $newAzureRmPolicyDefinitionParameters = @{
        Name        = $jsonDefinition.name
        DisplayName = $($definitionContent.DisplayName | ConvertTo-Json -Depth 20).replace('"', '')
        Description = $($definitionContent.Description | ConvertTo-Json -Depth 20).replace('"', '')
        Policy      = $($definitionContent.policyRule | ConvertTo-Json -Depth 20)
        Metadata    = $($definitionContent.Metadata | ConvertTo-Json -Depth 20)
        ApiVersion  = '2018-05-01'
        Verbose     = $true
    }

    if ($definitionContent.PSObject.Properties.Name -contains 'parameters')
    {
        $newAzureRmPolicyDefinitionParameters['Parameter'] = ConvertTo-Json -InputObject $definitionContent.parameters -Depth 15
    }

    if ($ManagementGroupName)
    {
        $newAzureRmPolicyDefinitionParameters['ManagementGroupName'] = $ManagementGroupName
    }

    Write-Verbose -Message "Publishing '$($jsonDefinition.properties.displayName)' ..."
    New-AzPolicyDefinition @newAzureRmPolicyDefinitionParameters
}
#EndRegion './Public/Publish-GuestConfigurationPolicy.ps1' 71
#Region './Public/Start-GuestConfigurationPackageRemediation.ps1' 0

<#
    .SYNOPSIS
        Starting to remediate a Guest Configuration policy package.

    .Parameter Path
        Relative/Absolute local path of the zipped Guest Configuration package.

    .Parameter Parameter
        Policy parameters.

    .Parameter Force
        Allows cmdlet to make changes on machine for remediation that cannot otherwise be changed.

    .Example
        Start-GuestConfigurationPackage -Path ./custom_policy/WindowsTLS.zip -Force

        $Parameter = @(
            @{
                ResourceType = "MyFile"            # dsc configuration resource type (mandatory)
                ResourceId = 'hi'       # dsc configuration resource property id (mandatory)
                ResourcePropertyName = "Ensure"       # dsc configuration resource property name (mandatory)
                ResourcePropertyValue = 'Present'     # dsc configuration resource property value (mandatory)
            })

        Start-GuestConfigurationPackage -Path ./custom_policy/AuditWindowsService.zip -Parameter $Parameter -Force

    .OUTPUTS
        None.
#>

function Start-GuestConfigurationPackageRemediation
{
    [CmdletBinding()]
    [OutputType()]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        [Switch]
        $Force,

        [Parameter()]
        [Hashtable[]]
        $Parameter = @()
    )

    $osPlatform = Get-OSPlatform

    if ($osPlatform -eq 'MacOS')
    {
        throw 'The Install-GuestConfigurationPackage cmdlet is not supported on MacOS'
    }

    $verbose = ($PSBoundParameters.ContainsKey('Verbose') -and ($PSBoundParameters['Verbose'] -eq $true))
    $systemPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
    if ($PSBoundParameters.ContainsKey('Force') -and $Force)
    {
        $withForce = $true
    }
    else
    {
        $withForce = $false
    }

    try
    {
        # Install the package
        $packagePath = Install-GuestConfigurationPackage -Path $Path -Force:$withForce -ErrorAction 'Stop'

        # The leaf part of the Path returned by Install-GCPackage will always be the BaseName of the MOF.
        $packageName = Get-GuestConfigurationPackageName -Path $packagePath

        # Confirm mof exists
        $packageMof = Join-Path -Path $packagePath -ChildPath "$packageName.mof"
        $dscDocument = Get-Item -Path $packageMof -ErrorAction 'SilentlyContinue'
        if (-not $dscDocument)
        {
            throw "Invalid Guest Configuration package, failed to find dsc document at $packageMof path."
        }

        # Throw if package is not set to AuditAndSet. If metaconfig is not found, assume Audit.
        $metaConfig = Get-GuestConfigurationPackageMetaConfig -Path $packagePath
        if ($metaConfig.Type -ne "AuditAndSet")
        {
            throw "Cannot run Start-GuestConfigurationPackage on a package that is not set to AuditAndSet. Current metaconfig contents: $metaconfig"
        }

        # Update mof values
        if ($Parameter.Count -gt 0)
        {
            Write-Debug -Message "Updating MOF with $($Parameter.Count) parameters."
            Update-MofDocumentParameters -Path $dscDocument.FullName -Parameter $Parameter
        }

        Write-Verbose -Message "Publishing policy package '$packageName' from '$packagePath'."
        Publish-DscConfiguration -ConfigurationName $packageName -Path $packagePath -Verbose:$verbose

        # Set LCM settings to force load powershell module.
        $metaConfigPath = Join-Path -Path $packagePath -ChildPath "$packageName.metaconfig.json"
        Write-Debug -Message "Setting 'LCM' Debug mode to force module import."
        Update-GuestConfigurationPackageMetaconfig -metaConfigPath $metaConfigPath -Key 'debugMode' -Value 'ForceModuleImport'
        Write-Debug -Message "Setting 'LCM' configuration mode to ApplyAndMonitor."
        Update-GuestConfigurationPackageMetaconfig -metaConfigPath $metaConfigPath -Key 'configurationMode' -Value 'ApplyAndMonitor'
        Set-DscLocalConfigurationManager -ConfigurationName $packageName -Path $packagePath -Verbose:$verbose

        # Run Deploy/Remediation
        Start-DscConfiguration -ConfigurationName $packageName -Verbose:$verbose
    }
    finally
    {
        $env:PSModulePath = $systemPSModulePath
    }
}
#EndRegion './Public/Start-GuestConfigurationPackageRemediation.ps1' 119
#Region './Public/Test-GuestConfigurationPackage.ps1' 0

<#
    .SYNOPSIS
        Tests a Guest Configuration policy package.

    .Parameter Path
        Full path of the zipped Guest Configuration package.

    .Parameter Parameter
        Policy parameters.

    .Example
        Test-GuestConfigurationPackage -Path ./custom_policy/WindowsTLS.zip

        $Parameter = @(
            @{
                ResourceType = "Service"            # dsc configuration resource type (mandatory)
                ResourceId = 'windowsService'       # dsc configuration resource property id (mandatory)
                ResourcePropertyName = "Name"       # dsc configuration resource property name (mandatory)
                ResourcePropertyValue = 'winrm'     # dsc configuration resource property value (mandatory)
            })

        Test-GuestConfigurationPackage -Path ./custom_policy/AuditWindowsService.zip -Parameter $Parameter

    .OUTPUTS
        Returns compliance details.
#>

function Test-GuestConfigurationPackage
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        [Hashtable[]]
        $Parameter = @(),

        [Parameter()]
        [Switch]
        $Force
    )

    if ($IsMacOS)
    {
        throw 'The Test-GuestConfigurationPackage cmdlet is not supported on MacOS'
    }

    # Determine if verbose is enabled to pass down to other functions
    $verbose = ($PSBoundParameters.ContainsKey("Verbose") -and ($PSBoundParameters["Verbose"] -eq $true))
    $systemPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Process")
    $gcBinPath = Get-GuestConfigBinaryPath
    $guestConfigurationPolicyPath = Get-GuestConfigPolicyPath
    if ($PSBoundParameters.ContainsKey('Force') -and $PSBoundParameters['Force'])
    {
        $withForce = $true
    }
    else
    {
        $withForce = $false
    }

    try
    {
        # Get the installed policy path, and install if missing
        $packagePath = Install-GuestConfigurationPackage -Path $Path -Verbose:$verbose -Force:$withForce


        $packageName = Get-GuestConfigurationPackageName -Path $packagePath
        Write-Debug -Message "PackageName: '$packageName'."
        # Confirm mof exists
        $packageMof = Join-Path -Path $packagePath -ChildPath "$packageName.mof"
        $dscDocument = Get-Item -Path $packageMof -ErrorAction 'SilentlyContinue'
        if (-not $dscDocument)
        {
            throw "Invalid Guest Configuration package, failed to find dsc document at '$packageMof' path."
        }

        # update configuration parameters
        if ($Parameter.Count -gt 0)
        {
            Write-Debug -Message "Updating MOF with $($Parameter.Count) parameters."
            Update-MofDocumentParameters -Path $dscDocument.FullName -Parameter $Parameter
        }

        Write-Verbose -Message "Publishing policy package '$packageName' from '$packagePath'."
        Publish-DscConfiguration -ConfigurationName $packageName -Path $packagePath -Verbose:$verbose

        # Set LCM settings to force load powershell module.
        Write-Debug -Message "Setting 'LCM' Debug mode to force module import."
        $metaConfigPath = Join-Path -Path $packagePath -ChildPath "$packageName.metaconfig.json"
        Update-GuestConfigurationPackageMetaconfig -metaConfigPath $metaConfigPath -Key 'debugMode' -Value 'ForceModuleImport'
        Set-DscLocalConfigurationManager -ConfigurationName $packageName -Path $packagePath -Verbose:$verbose

        $inspecProfilePath = Get-InspecProfilePath
        Write-Debug -Message "Clearing Inspec profiles at '$inspecProfilePath'."
        Remove-Item -Path $inspecProfilePath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Verbose -Message "Getting Configuration resources status."
        $getResult = @()
        $getResult = $getResult + (Get-DscConfiguration -ConfigurationName $packageName -Verbose:$verbose)
        return $getResult
    }
    finally
    {
        $env:PSModulePath = $systemPSModulePath
    }
}
#EndRegion './Public/Test-GuestConfigurationPackage.ps1' 113


# SIG # Begin signature block
# MIIjhQYJKoZIhvcNAQcCoIIjdjCCI3ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAdT/Mx3DpQFcLy
# uYNzTDs+dBtNyiN5/TUW9rghwH3jvaCCDYEwggX/MIID56ADAgECAhMzAAAB32vw
# LpKnSrTQAAAAAAHfMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAxMjE1MjEzMTQ1WhcNMjExMjAyMjEzMTQ1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC2uxlZEACjqfHkuFyoCwfL25ofI9DZWKt4wEj3JBQ48GPt1UsDv834CcoUUPMn
# s/6CtPoaQ4Thy/kbOOg/zJAnrJeiMQqRe2Lsdb/NSI2gXXX9lad1/yPUDOXo4GNw
# PjXq1JZi+HZV91bUr6ZjzePj1g+bepsqd/HC1XScj0fT3aAxLRykJSzExEBmU9eS
# yuOwUuq+CriudQtWGMdJU650v/KmzfM46Y6lo/MCnnpvz3zEL7PMdUdwqj/nYhGG
# 3UVILxX7tAdMbz7LN+6WOIpT1A41rwaoOVnv+8Ua94HwhjZmu1S73yeV7RZZNxoh
# EegJi9YYssXa7UZUUkCCA+KnAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUOPbML8IdkNGtCfMmVPtvI6VZ8+Mw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDYzMDA5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAnnqH
# tDyYUFaVAkvAK0eqq6nhoL95SZQu3RnpZ7tdQ89QR3++7A+4hrr7V4xxmkB5BObS
# 0YK+MALE02atjwWgPdpYQ68WdLGroJZHkbZdgERG+7tETFl3aKF4KpoSaGOskZXp
# TPnCaMo2PXoAMVMGpsQEQswimZq3IQ3nRQfBlJ0PoMMcN/+Pks8ZTL1BoPYsJpok
# t6cql59q6CypZYIwgyJ892HpttybHKg1ZtQLUlSXccRMlugPgEcNZJagPEgPYni4
# b11snjRAgf0dyQ0zI9aLXqTxWUU5pCIFiPT0b2wsxzRqCtyGqpkGM8P9GazO8eao
# mVItCYBcJSByBx/pS0cSYwBBHAZxJODUqxSXoSGDvmTfqUJXntnWkL4okok1FiCD
# Z4jpyXOQunb6egIXvkgQ7jb2uO26Ow0m8RwleDvhOMrnHsupiOPbozKroSa6paFt
# VSh89abUSooR8QdZciemmoFhcWkEwFg4spzvYNP4nIs193261WyTaRMZoceGun7G
# CT2Rl653uUj+F+g94c63AhzSq4khdL4HlFIP2ePv29smfUnHtGq6yYFDLnT0q/Y+
# Di3jwloF8EWkkHRtSuXlFUbTmwr/lDDgbpZiKhLS7CBTDj32I0L5i532+uHczw82
# oZDmYmYmIUSMbZOgS65h797rj5JJ6OkeEUJoAVwwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVWjCCFVYCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAd9r8C6Sp0q00AAAAAAB3zAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgoJoUiP7c
# AwnG188Um1ldwTRvrZXE4+Pg2Q/FtARrHN4wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQA38qmEeFBbPdrzJD1PNflhk+pVItahEMc32uEEHkz+
# vKdCu+iwrK1fmm5l27aQuBePXkDR1yjkl67NxZgNSEsn81CzxE2Ai+3DG3es3wDJ
# 2QXjbtElvr+8DIZPCysgg2SbtN7RVVszaCGp72bpCqG6iS+3NODQ+3cFGjaEeo5O
# iDQJspfVZ0DziIe3m6yw2us6uMAG8yA09jtkjJc/YUCPnT7JfmD/CVz4UxPNyMuk
# SoY/kn1ApTH7S4A0uRy+9FiITQD10uudRFcTz+D6sqhI2plEaQ5Ts/fKpmXaU5JY
# JVV0K8gNQD4G9gtQADX3vWTd71E0ddLrSFvnTgMoaugpoYIS5DCCEuAGCisGAQQB
# gjcDAwExghLQMIISzAYJKoZIhvcNAQcCoIISvTCCErkCAQMxDzANBglghkgBZQME
# AgEFADCCAVAGCyqGSIb3DQEJEAEEoIIBPwSCATswggE3AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIE99xH3B0gRPkTQ9GbzZREO7kH2oeTveJtOYjfrF
# ysRNAgZhQ6mqNAsYEjIwMjExMDE1MjE1MDM1LjY3WjAEgAIB9KCB0KSBzTCByjEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046M0U3QS1FMzU5LUEyNUQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2Wggg48MIIE8TCCA9mgAwIBAgITMwAAAVIwS12JrOZwRwAAAAABUjAN
# BgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0y
# MDExMTIxODI2MDVaFw0yMjAyMTExODI2MDVaMIHKMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozRTdBLUUzNTktQTI1
# RDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBAK7MboSJmHS1oJJuzAyK6kxNidtugXOO
# PUO4Ntu9PRFcoEJWX+6YD5TLbXgOYeIWGR65F2UsHTJrlL26bloqvuUEGpnO+0qA
# Y2AJFsNMb1i7qTMPM9PNBG6VUi+hZXLSAhOcTKgnU7ebkg+mwsE1AJ1eyH7dNkXv
# ckBy5vbVufGb/izF7jNN1t220Gupfz8kkXZUScA/4wG8XZRBKjpdQBpMoL8c8M8J
# x78iw2gDHEsMjXAeEiWqNEGe3gczkdwoetmu8f68eeKGKR2UTOHd+NAWjCTV8bs9
# WGY7rQ7m9V2oD4f3fXiEcQ1AjRxuj5KRKLxJIlIs2LGCPR5Z49OHulsCAwEAAaOC
# ARswggEXMB0GA1UdDgQWBBSE3a7arCPWXZzaH+RQsO4FEmx7FDAfBgNVHSMEGDAW
# gBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0Ff
# MjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEw
# LTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0G
# CSqGSIb3DQEBCwUAA4IBAQBVxSdx8WpJrNBsMRd/d3XT+6mJZBTkd1NvAb2/1t5U
# gNobigQvIhw0Tp7oJs4EyU9T6yalhhycreO5w2oKHCq4ubF2LaI/LiJDq+MB0Gn3
# 5UVaWsGpSw1dnOMKmAwJmPpu7xerQ2d2XhbIFsjQmS7ry9Q0bjCwx0o/d3P7UzOT
# 1JSZrePsfI0Dnn12j2eEqahkyfl21/TdC/GVoTAwBo+T3G5S/0E3xw28WelaTiYs
# RFBbq0DetcrSygQhIpNgbs6x7ugxdkNg9bF/2gWFgrNnD9LCeF0GiPZLl7JgTcC4
# X9lfNHeF2nf9cbNl450RF8XLWsLtkHCEMhqN4UyLncafMIIGcTCCBFmgAwIBAgIK
# YQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0
# NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX7
# 7XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM
# 1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHP
# k0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3Ws
# vYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw
# 6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHi
# MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVt
# VTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0T
# AQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNV
# HR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9w
# cm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEE
# TjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGS
# MIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4y
# IB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAu
# IB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+
# zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKK
# dsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/Uv
# eYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4z
# u2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHim
# bdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlX
# dqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHh
# AN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A
# +xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdC
# osnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42ne
# V8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nf
# j950iEkSoYICzjCCAjcCAQEwgfihgdCkgc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjNFN0EtRTM1OS1BMjVE
# MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYF
# Kw4DAhoDFQC/bp5Ulq6ZyZNyF3qGprJAw0NeW6CBgzCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5RRi3DAiGA8yMDIx
# MTAxNjA0MjgxMloYDzIwMjExMDE3MDQyODEyWjB3MD0GCisGAQQBhFkKBAExLzAt
# MAoCBQDlFGLcAgEAMAoCAQACAgc5AgH/MAcCAQACAhFDMAoCBQDlFbRcAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAJG+8MKGsrj8goUM4fNCy5JPW5igWgiKM
# Gjde4sbxhnzRZCy/KLFlvUWrK8sa2yKbQOuxJhblm1myNBg7B6NjS5EoxKtfp1Vr
# J0JYgwVkDOP6aSVJ7ktbyG3Uv7rwA9USRG8P93nx6XVXkPeKDmRms87/ecWSO1sO
# uKzA+yZN0HcxggMNMIIDCQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAVIwS12JrOZwRwAAAAABUjANBglghkgBZQMEAgEFAKCCAUowGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCQ2PJ/c4Fs
# XPqQV0vcDTunhwWBJrszhueMS1rTX9S4bTCB+gYLKoZIhvcNAQkQAi8xgeowgecw
# geQwgb0EIJPuXMejiyVQjF8QanwtdA2KT95wrq+64ZYhyYGuuyemMIGYMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAFSMEtdiazmcEcAAAAA
# AVIwIgQgHCw1YBt4yE7WiN2BbvP9tOE3AXpBXXzuixhUJf+C8IcwDQYJKoZIhvcN
# AQELBQAEggEAJMNth3/tljE0CSKipXUPwWZqTem7VxWjb92mJpszxdsgqVebdFEf
# rMcuJ5qvgi4t5BviZxzrhBC4lEAAla4XRlOIWGXDwQpvMVFfzdvhrXcZjdzHlzrV
# o/e4gb89tCEvX/Vw0MqTeHdU4esM5iQ0PP8tK7RHrCJHqiMUMjBNrIXMb6XkKqsW
# YhLxqb3PHBvcHiWYDppFrevHEz+AQqQUY1XqVnw+gYepuG7cqdPfH3ftL1yK+mGQ
# SmAj5K6ozJ78IbylTln8Hz3rTY/kzZHlNuiYzVH2wzz1IgsW0V6tL3PgOXt93Mxj
# ceyDkKWSWPGnc9YlkJ5270jj6RAgRUntWw==
# SIG # End signature block
