<#
.SYNOPSIS
Gets your computer ready to develop the Prism module.

.DESCRIPTION
The init.ps1 script makes the configuraion changes necessary to get your computer ready to develop for the
Prism module. It:


.EXAMPLE
.\init.ps1

Demonstrates how to call this script.
#>
[CmdletBinding()]
param(
)

Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Run in a background job so that old PackageManagement assemblies don't get loaded.
$job = Start-Job {
    $InformationPreference = 'Continue'
    $psGalleryRepo = Get-PSRepository -Name 'PSGallery'
    $repoToUse = $psGalleryRepo.Name
    # On Windows 2012 R2, Windows PowerShell 5.1, and .NET 4.6.2, PSGallery's URL ends with a '/'.
    if( -not $psGalleryRepo -or $psgalleryRepo.SourceLocation -ne 'https://www.powershellgallery.com/api/v2' )
    {
        $repoToUse = 'PSGallery2'
        Register-PSRepository -Name $repoToUse `
                              -InstallationPolicy Trusted `
                              -SourceLocation 'https://www.powershellgallery.com/api/v2' `
                              -PackageManagementProvider $psGalleryRepo.PackageManagementProvider
    }

    $maxPkgMgmtVersion = '1.4.7'
    [Version] $minPkgMgmtVersion = '1.4.7'  # '1.3.2' once Whiskey is updated to support this as minimum version.
    if( -not (Get-Module -Name 'PackageManagement' -ListAvailable | Where-Object 'Version' -ge $minPkgMgmtVersion) )
    {
        Write-Information -MessageData "Installing PowerShell module PackageManagement $($maxPkgMgmtVersion)."
        Install-Module -Name 'PackageManagement' -RequiredVersion $maxPkgMgmtVersion -Repository $repoToUse -AllowClobber -Force
    }

    [Version] $minPsGetVersion = '2.2.5'  # '2.1.3' once Whiskey is updated to support this as minimum version.
    if( -not (Get-Module -Name 'PowerShellGet' -ListAvailable | Where-Object 'Version' -ge $minPsGetVersion) )
    {
        $psGetVersion = '2.2.5'
        Write-Information -MessageData "Installing PowerShell module PowerShellGet $($psGetVersion)."
        Install-Module -Name 'PowerShellGet' -RequiredVersion $psGetVersion -Repository $repoToUse -AllowClobber -Force
    }

    Get-Module -Name 'PackageManagement' -ListAvailable |
        Where-Object Version -gt $maxPkgMgmtVersion |
        ForEach-Object {
            Write-Information -MessageData "Uninstalling PowerShell module $($_.Name) $($_.Version)."
            Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force
        }
}

if( (Get-Command -Name 'Receive-Job' -ParameterName 'AutoRemoveJob') )
{
    $job | Receive-Job -AutoRemoveJob -Wait
}
else
{
    $job | Wait-Job | Receive-Job
    $job | Remove-Job
}

Get-Module | Format-Table -Auto | Out-String
Get-Module 'PackageManagement', 'PowerShellGet' -ListAvailable | Format-Table -Auto | Out-String