[CmdletBinding()]
param(
)

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

function Invoke-InstallJob
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [String] $Name,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Version] $MaximumVersion
    )

    Write-Debug "Installing $($Name) $($MaximumVersion) in a background job."
    Start-Job {
        $DebugPreference = $using:DebugPreference
        $VerbosePreference = $using:VerbosePreference
        $name = $using:Name
        $version = $using:MaximumVersion

        if( $name -eq 'PackageManagement' )
        {
            # If we previously installed PowerShellGet, it may have installed a too-new for Whiskey version of
            # PackageManagement. We deleted the too-new version of PackageManagement, which means the version of
            # PowerShellGet we installed won't import (its dependency is gone), so we try to import the newest
            # version of PowerShellGet that's installed in order to install PackageManagement
            $modules =
                Get-Module -Name 'PowerShellGet' -ListAvailable | Sort-Object -Property 'Version'
            foreach( $module in $modules )
            {
                $importError = $null
                try
                {
                    Write-Debug "Attempting import of $($module.Name) $($module.Version) from ""$($module.Path)""."
                    $module | Import-Module -ErrorAction SilentlyContinue -ErrorVariable 'importError'
                    if( (Get-Module -Name 'PowerShellGet') )
                    {
                        Write-Debug "Imported PowerShellGet $($module.Version)."
                        break
                    }
                    if( $importError )
                    {
                        Write-Debug "Errors importing $($module.Name) $($module.Version): $($importError)"
                        $Global:Error.RemoveAt(0)
                    }
                }
                catch
                {
                    Write-Debug "Exception importing $($module.Name) $($module.Version): $($_)"
                }
            }
        }

        $moduleToInstall = Find-Module -Name $name -RequiredVersion $version | Select-Object -First 1
        Write-Information "Saving PowerShell module $($name) $($version) in current user scope."
        $msg = "Installing $($moduleToInstall.Name) $($moduleToInstall.Version) from " +
               "$($moduleToInstall.RepositorySourceLocation) to current user scope."
        Write-Debug $msg
        $moduleToInstall | Install-Module -Force -AllowClobber -Scope CurrentUser
        Get-Module -Name $name -ListAvailable | Where-Object 'Version' -EQ $moduleToInstall.Version
    } | Wait-InstallJob
    Write-Debug "$($Name) $($MaximumVersion) installation background job complete."
}

function Test-ModuleInstalled
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [String] $Name,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Version] $MinimumVersion,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Version] $MaximumVersion,

        [switch] $PassThru
    )

    $module =
        Get-Module -Name $Name -ListAvailable |
        Where-Object 'Version' -GE $MinimumVersion |
        Where-Object 'Version' -LE $MaximumVersion

    if( $PassThru )
    {
        return $module
    }

    return $null -ne $module
}

function Wait-InstallJob
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Job
    )

    process
    {
        if( (Get-Command -Name 'Receive-Job' -ParameterName 'AutoRemoveJob') )
        {
            $Job | Receive-Job -AutoRemoveJob -Wait
        }
        else
        {
            $Job | Wait-Job | Receive-Job
            $Job | Remove-Job
        }
    }
}

$psGet = [pscustomobject]@{
    Name = 'PowerShellGet';
    MinimumVersion = '2.1.5';
    MaximumVersion = '2.2.5';
}

$pkgMgmt =  [pscustomobject]@{
    Name = 'PackageManagement';
    MinimumVersion = '1.3.2';
    MaximumVersion = '1.4.7';
}

$requiredModules = @( $psGet, $pkgMgmt )

Get-Module -Name $requiredModules.Name -ListAvailable | Format-Table -Auto | Out-String | Write-Debug

if( -not ($psGet | Test-ModuleInstalled) )
{
    $psGet | Invoke-InstallJob
}

$psGetModule = $psGet | Test-ModuleInstalled -PassThru
# Make sure Package Management minimum version matches PowerShellGet's minium version.
$pkgMgmt.MinimumVersion =
    $psGetModule.RequiredModules |
    Where-Object 'Name' -EQ $pkgMgmt.Name |
    Select-Object -ExpandProperty 'Version' |
    Sort-Object -Descending |
    Select-Object -First 1

if( -not ($pkgMgmt | Test-ModuleInstalled) )
{
    # PowerShellGet depends on PackageManagement, so Save-Module/Install-Module will install the latest version of
    # PackageManagement if a version PowerShellGet can use isn't installed. Whiskey may not support the latest version.
    # So, if Save-Module installed an incompatible version of PackageManagement, we need to remove it.
    Get-Module -Name $pkgMgmt.Name -ListAvailable |
        Where-Object 'Version' -GT $pkgMgmt.MaximumVersion |
        ForEach-Object {
            $pathToDelete = $_ | Split-Path -Parent
            $msg = "Deleting unsupported $($_.Name) $($_.Version) module from " +
                    """$($pathToDelete | Resolve-Path -Relative)""."
            Write-Debug $msg
            Remove-Item -Path $pathToDelete -Recurse -Force
        }

    $pkgMgmt | Invoke-InstallJob
}

# PowerShell will auto-import PackageManagement because PowerShellGet depends on it.
Import-Module -Name 'PowerShellGet' `
              -MinimumVersion $psGet.MinimumVersion `
              -MaximumVersion $psGet.MaximumVersion `
              -Global

if( -not (Get-Module -Name 'Prism' -ListAvailable) )
{
    $prismToInstall = Find-Module -Name 'Prism' | Select-Object -First 1
    $prismToInstall | Install-Module -Force -AllowClobber -Scope CurrentUser
    Get-Module -Name $prismToInstall.Name -ListAvailable | Where-Object 'Version' -EQ $prismToInstall.Version
}

Write-Debug 'Imported PowerShellGet and PackageManagement modules.'
Get-Module -Name $pkgMgmt.Name, $psGet.Name | Format-Table -Auto | Out-String | Write-Debug

if( (Test-Path -Path 'env:APPVEYOR') )
{
    Get-Module -Name $pkgMgmt.Name, $psGet.Name, 'Prism' -ListAvailable | Format-Table -Auto | Out-String | Write-Debug
}
