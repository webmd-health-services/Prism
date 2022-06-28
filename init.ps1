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

    [Version] $psGetVersion = '2.2.5'
    if( -not (Get-Module -Name 'PowerShellGet' -ListAvailable | Where-Object 'Version' -ge $psGetVersion) )
    {
        Write-Information -MessageData "Installing PowerShell module PowerShellGet $($psGetVersion)."
        Install-Module -Name 'PowerShellGet' -RequiredVersion $psGetVersion -Repository $repoToUse -AllowClobber -Force
    }

    [Version] $pkgMgmtVersion = '1.4.7'
    if( -not (Get-Module -Name 'PackageManagement' -ListAvailable | Where-Object 'Version' -ge $pkgMgmtVersion) )
    {
        Write-Information -MessageData "Installing PowerShell module PackageManagement $($pkgMgmtVersion)."
        Install-Module -Name 'PackageManagement' -RequiredVersion $pkgMgmtVersion -Repository $repoToUse -AllowClobber -Force
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