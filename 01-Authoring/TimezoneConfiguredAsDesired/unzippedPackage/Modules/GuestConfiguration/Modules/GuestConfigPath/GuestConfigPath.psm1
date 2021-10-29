#Region './prefix.ps1' 0
Set-StrictMode -Version latest
$ErrorActionPreference = 'Stop'
$ReleaseVersion = '0.0.0'
#EndRegion './prefix.ps1' 4
#Region './Private/Get-GuestConfigPath.ps1' 0
function Get-GuestConfigPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $platform = Get-OSPlatform

    if ($platform -eq 'Windows')
    {
        Join-path -Path $env:ProgramData -ChildPath 'GuestConfig'
    }
    else
    {
        '/var/lib/GuestConfig'
    }
}
#EndRegion './Private/Get-GuestConfigPath.ps1' 18
#Region './Public/Get-GuestConfigAssignmentReportFilePath.ps1' 0
function Get-GuestConfigAssignmentReportFilePath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ConfigurationName
    )

    $guestConfigReportFolderPath = Get-GuestConfigAssignmentReportFolderPath -ConfigurationName $ConfigurationName

    $reportFilePath = Join-Path $guestConfigReportFolderPath "$($ConfigurationName)_Compliant.json"
    if(Test-Path $reportFilePath) {
        return $reportFilePath
    }

    $reportFilePath = Join-Path $guestConfigReportFolderPath "$($ConfigurationName)_NonCompliant.json"
    if(Test-Path $reportFilePath) {
        return $reportFilePath
    }

    throw "Failed to find assignment report at '$($guestConfigReportFolderPath)' location"
}
#EndRegion './Public/Get-GuestConfigAssignmentReportFilePath.ps1' 27
#Region './Public/Get-GuestConfigAssignmentReportFolderPath.ps1' 0
function Get-GuestConfigAssignmentReportFolderPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ConfigurationName
    )

    $binRootFolder = Get-GuestConfigBinaryRootPath
    $releaseVersionfolder = Join-Path -Path $binRootFolder -ChildPath $global:ReleaseVersion
    $guestConfigReportFolderPath = Join-Path -Path $releaseVersionfolder -ChildPath 'reports'
    return $guestConfigReportFolderPath
}
#EndRegion './Public/Get-GuestConfigAssignmentReportFolderPath.ps1' 18
#Region './Public/Get-GuestConfigBinaryPath.ps1' 0
function Get-GuestConfigBinaryPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param ()

    $binRootFolder = Get-GuestConfigBinaryRootPath
    $releaseVersionfolder = Join-Path -Path $binRootFolder -ChildPath $global:ReleaseVersion
    $guestConfigBinaryPath = Join-Path -Path $releaseVersionfolder -ChildPath 'GC'
    Write-Debug -Message "Guest Config Binary Path is: '$guestConfigBinaryPath'."

    $guestConfigBinaryPath
}
#EndRegion './Public/Get-GuestConfigBinaryPath.ps1' 15
#Region './Public/Get-GuestConfigBinaryRootPath.ps1' 0

function Get-GuestConfigBinaryRootPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    Join-Path -Path (Get-GuestConfigPath) -ChildPath 'bin'
}
#EndRegion './Public/Get-GuestConfigBinaryRootPath.ps1' 10
#Region './Public/Get-GuestConfigLogPath.ps1' 0
function Get-GuestConfigLogPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param ()

    $logFolder = Join-Path -Path (Get-GuestConfigPath) -ChildPath 'gc_agent_logs'
    $logPath = Join-Path -Path $logFolder -ChildPath 'gc_agent.json'

    return $logPath
}
#EndRegion './Public/Get-GuestConfigLogPath.ps1' 13
#Region './Public/Get-GuestConfigPolicyPath.ps1' 0
function Get-GuestConfigPolicyPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    Join-path -Path $(Get-GuestConfigPath) -ChildPath 'policy'
}
#EndRegion './Public/Get-GuestConfigPolicyPath.ps1' 9
#Region './Public/Get-GuestConfigurationModulePath.ps1' 0
function Get-GuestConfigurationModulePath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    (Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Parent.FullName
}
#EndRegion './Public/Get-GuestConfigurationModulePath.ps1' 9
#Region './Public/Get-GuestConfigWorkerBinaryPath.ps1' 0
function Get-GuestConfigWorkerBinaryPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param ()

    $gcBinPath = Get-GuestConfigBinaryPath
    $gcWorkerPath = Join-Path $gcBinPath 'gc_worker.exe'

    if (-not $IsWindows)
    {
        $gcWorkerPath = Join-Path $gcBinPath 'gc_worker'
    }

    return $gcWorkerPath
}
#EndRegion './Public/Get-GuestConfigWorkerBinaryPath.ps1' 18
#Region './Public/Get-InspecProfilePath.ps1' 0
function Get-InspecProfilePath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    Join-Path -Path $(Get-GuestConfigBinaryPath) -ChildPath 'inspec'
}
#EndRegion './Public/Get-InspecProfilePath.ps1' 9
#Region './Public/Get-OSPlatform.ps1' 0
function Get-OSPlatform
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $platform = 'Windows'

    if ($PSVersionTable.PSEdition -eq 'Desktop')
    {
        $platform = 'Windows'
    }
    elseif ($PSVersionTable.PSEdition -eq 'Core')
    {
        if ($IsWindows)
        {
            $platform = 'Windows'
        }
        elseif ($IsLinux)
        {
            $platform = 'Linux'
        }
        elseif ($IsMacOS)
        {
            $platform = 'MacOS'
        }
    }

    $platform
}
#EndRegion './Public/Get-OSPlatform.ps1' 31
#Region './Public/InitReleaseVersionInfo.ps1' 0

function InitReleaseVersionInfo
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Version
    )

    $global:ReleaseVersion = $Version
}
#EndRegion './Public/InitReleaseVersionInfo.ps1' 14
#Region './Public/Write-GCOperationConsoleMessages.ps1' 0
function Write-GCOperationConsoleMessages
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    param ()

    $logPath = Get-GuestConfigLogPath
    $logs = ConvertFrom-Json (Get-Content $logPath -Raw)
    $logs | % {
        if($_.type -eq 'warning')
        {
            Write-Warning $_.message
        }
        elseif($_.type -eq 'error')
        {
            Write-Error $_.message
        }
        else
        {
            Write-Verbose $_.message
        }
    }
}
#EndRegion './Public/Write-GCOperationConsoleMessages.ps1' 24

# SIG # Begin signature block
# MIIjkgYJKoZIhvcNAQcCoIIjgzCCI38CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDqmIzSayuEgQn/
# TITRvkxAy6LbrI4m9S3NOBUdW3acwqCCDYEwggX/MIID56ADAgECAhMzAAAB32vw
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVZzCCFWMCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAd9r8C6Sp0q00AAAAAAB3zAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgprC9CGUd
# g5YwLGQaKH7yakjvBRIXxatoylEal8eLXucwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAk6ylXu1/l8VCjb9xECRmH66P+fStfZFcxowdLlAL4
# LWVqmSHae6fJdpfEq2IQYyjwqNxhk1FSchR7lpJsnsGtQrPUagx6d+L13F3vQwYZ
# zDKp8wNlF7TZce244Io3ihZGWxWqMhSejO5fAnpylnRJnr3TbS5bvtaS0MulUAwx
# UtdneyCIYRFftrjKzsc0AqEecNoV8YOmPdy49+XxG77sZkVnvrcfBlcci+e70gp/
# mBtzFayi0UB9gOC6NDYyS7Wb8lLBMAt3NDUPq6KZ/S/brBI2JFnOh7fTbqmmhVHL
# 3qvnvFjzj2WT+JDhLZXFFuz03Y0Z3AqfJWjJnlP6uzM2oYIS8TCCEu0GCisGAQQB
# gjcDAwExghLdMIIS2QYJKoZIhvcNAQcCoIISyjCCEsYCAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIFhdU+lqN2ezvAGI5A4TNjZ+wwrdrJmusSVLOwd2
# xiZdAgZhRNPjO+gYEzIwMjExMDE1MjE1MDMyLjgwN1owBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjo2MEJDLUUzODMtMjYzNTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCDkQwggT1MIID3aADAgECAhMzAAABWiy5bkQ0y28oAAAA
# AAFaMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIxMDExNDE5MDIxNloXDTIyMDQxMTE5MDIxNlowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo2MEJD
# LUUzODMtMjYzNTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALC9XBxXDa0nCK70Hf+G
# ih6NxRl1mAhzFJdok8bs3xpJ87TM28rEeHkZAaE+Kb9Gi9UvTpQ3zrEWyWSpIQky
# xv/Wf0cIhA1mJOqyu20TN3l96ZvgzYrzO/rQlPvbKW79oAO4+YFsekQCtrzM9hQo
# S5BYGwPh9Qz66BuSxH9QweywNBQsjkVoikpBxkS+EXSIzpba2afvnRMX7LLe2ery
# c+PlPXmTSOfH1WNykc25u9zo6ZX0gAd4jUpBzdMLnHCtE62bL2PO00cmAJsitqga
# ov+3lFrfd0sPACwTGO9iymlJlb2savwjqSnj5RzG4RxG6rU2i7etbnQTozR73OHM
# GOUCAwEAAaOCARswggEXMB0GA1UdDgQWBBRkcyU/9RyPkn7QBoXZOTQ8wN4xZzAf
# BgNVHSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBH
# hkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNU
# aW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUF
# BzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0
# YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAAAG3sfFgbUiw4gWMV8VOxlbIG/CIM
# SiciDtIZnPL84OMN4lJeV5LeJr+HYBcox5ruWZm49K29iBmJv6ViXMtP81pYZ1EF
# M7306Y+zLIh/tS574PeWsHvPD0QOxQ4HOM2GNPvFAdUvo8z5pgV/5E+lPu61uUCI
# BTDESiHO+N7ragqb3METPqRKPLNAJcKPDcalKznmGPlnzY6P1zop/7a90VcBHRKK
# Q/hTvn/8C8Y6b+Mvk5kYJh67KNbVVcuuBWyFSMZTHGenHnuHVg9svH7+lm/V/wIb
# ZUKKJJO0HQmyodySeD/JLC7NNsDYRpFN+29dLRtx0eWyZosJmT8qKbBIMIIGcTCC
# BFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJv
# b3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcN
# MjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0
# VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEw
# RA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQe
# dGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKx
# Xf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4G
# kbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEA
# AaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0g
# AQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYB
# BQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUA
# bQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOh
# IW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS
# +7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlK
# kVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon
# /VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOi
# PPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/
# fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCII
# YdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0
# cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7a
# KLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQ
# cdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+
# NR4Iuto229Nfj950iEkSoYIC0jCCAjsCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBP
# cGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo2
# MEJDLUUzODMtMjYzNTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIjCgEBMAcGBSsOAwIaAxUAzIAFmL3GHHWcAJYi3haGwlplGi6ggYMwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIF
# AOUUO4YwIhgPMjAyMTEwMTUyMTQwMjJaGA8yMDIxMTAxNjIxNDAyMlowdzA9Bgor
# BgEEAYRZCgQBMS8wLTAKAgUA5RQ7hgIBADAKAgEAAgIjvgIB/zAHAgEAAgIRhjAK
# AgUA5RWNBgIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIB
# AAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAH/kYjHUzUzoKhEj
# 1nlF3/J2TjoVKczedcipunwnsQMHpjDoRkgQBL5A3xHQ9erFRNZHAslD+F9IJBTf
# PVSxiDk/DIqLTdfYcK8ezlRvOwwR9hDsx8WblZ7vkc+XvYg/Bkv7cYrEZpUvOuqc
# +61YW55M2jMDidDq24/+yqeng8KpMYIDDTCCAwkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAFaLLluRDTLbygAAAAAAVowDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQglNaB+OKdjxbrQSFw6Qc4MDlaYB2Uvu4s5K9tNB0RKOcwgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCCT/KgmdMSy5F0ww4Iar9cmf5Is3pM0hUuIInL5
# bbF/sDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# Wiy5bkQ0y28oAAAAAAFaMCIEII7kqgdk/h8HHlR+q/rm4QC8HLA7ATAhlzORthIg
# lQ6jMA0GCSqGSIb3DQEBCwUABIIBABeGasIuAaFcgtEZYkBiDgpkQAro3VXlBb1g
# IhL4JwpKmksJuqCpsiYzpt4J4PEoo0RhBTM+OCf23ztTaouoj+dE41b2mNiMRKH7
# Yb9VJ5X9fzkq0adBn4/8ovfb/vmwoux5g0hA8VZmsJp9e17nQeh4TahBk+Oynkqi
# 1RNXDxoHmyNJNyyV7fUPJGb5hA3dW1KWC5PYRVx2eqPdWAjsStyWRVBzrJnSxeDb
# +4IDqSn153MaDNkR77d9hBgPZnnqC7izvTtR+ROR532gwKq+z7hEW9+U5yLixexl
# KY9gvf7J46iODkFng6w3ckmeUshw91GLa2AWEq4/b1UevN0mI68=
# SIG # End signature block
