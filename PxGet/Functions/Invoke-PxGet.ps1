function Invoke-PxGet
{
    <#
    .SYNOPSIS
    Invokes PxGet.
    
    .DESCRIPTION
    A tool similar to nuget but for PowerShell modules. A config file in the root of a repository that specifies 
    what modules should be installed into the PSModules directory of the repository. 

    .EXAMPLE
    Invoke-PxGet 'install'

    Demonstrates how to call this function to install required PSModules.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('install')]
        [String] $Command
    )
 
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $origModulePath = $env:PSModulePath
    $psmodulesPath = Join-Path -Path $(Get-RootDirectory) -ChildPath 'PSModules'
    if( -not (Test-Path -Path $psmodulesPath) )
    {
        New-Item -Path $psmodulesPath -ItemType 'Directory' | Out-Null
    }
    
    try
    {
        # pxget should ship with its own private copies of PackageManagement and PowerShellGet. Setting PSModulePath
        # to pxget module's Modules directory ensures no other package modules get loaded.
        $env:PSModulePath = Join-Path -Path $(Get-RootDirectory) -ChildPath 'PSModules' -Resolve
        Import-Module -Name 'PackageManagement'
        Import-Module -Name 'PowerShellGet'

        $moduleNames = @()
        $pxModules = Get-Content -Path ($(Get-RootDirectory) + '\pxget.json') | ConvertFrom-Json
 
        foreach ($pxModule in $pxModules.PSModules) 
        {
            $moduleNames += $pxModule.Name
        }
        $modules = Find-Module -Name $moduleNames

        # We only care if the module is in PSModules right now. Later we'll allow dev dependencies, which can be
        # installed globally.
        $env:PSModulePath = $psModulesPath
 
        foreach( $pxModule in $pxModules.PSModules )
        {
            # $allowPrerelease = [wildcardpattern]::ContainsWildcardCharacters($pxModule.Version)
            $allowPrerelease = $pxModule.Version.Contains('-')
            
            if( $allowPrerelease)
            {
                # Find module again but with AllVersions and AllowPrerelease
                $modulesWithPrelease = Find-Module -Name $pxModule.Name -AllowPrerelease -AllVersions
                $moduleToInstall = FindModuleFromList -Modules $modulesWithPrelease -ModuleToFind $pxModule -AllowPrerelease $allowPrerelease
            }
            else
            {
                $moduleToInstall = FindModuleFromList -Modules $modules -ModuleToFind $pxModule -AllowPrerelease $allowPrerelease
            }
 
            if( -not $moduleToInstall )
            {
                Write-Error "Module $($pxModule.Name) was not found!"
                continue
            }
 
            $installedModule =
                Get-Module -Name $pxModule.Name -List |
                # Won't be this easy. You'll need to take into account prerelease metadata.
                Where-Object 'Version' -eq $moduleToInstall.Version
            # The latest version that matches the version in the pxget.json file is already installed
            if( $installedModule )
            {
                continue
            }
 
            # Not installed. Install it. We pipe it so the repository of the module is also used.
            $moduleToInstall | Save-Module -Path $psmodulesPath
        }
    }
    finally
    {
        $env:PSModulePath = $origModulePath
    }
}

Set-Alias -Name 'pxget' -Value 'Invoke-PxGet'

function FindModuleFromList
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]] $Modules,

        [Parameter(Mandatory)]
        [PSCustomObject] $ModuleToFind,

        [Parameter(Mandatory)]
        [Boolean] $AllowPrerelease
    )

    $moduleToInstall =
        $Modules |
        Where-Object 'Name' -eq $ModuleToFind.Name |
        Where-Object 'Version' -like $ModuleToFind.Version |
        Where-Object {
            if( $AllowPrerelease )
            {
                return $true
            }
            return $_.Version -notmatch '-[A-Za-z0-9.-]+(\+[A-Za-z0-9.-]+)?$'
        } |
        Select-Object -First 1
    
    return $moduleToInstall
}

function Get-RootDirectory
{
    return (Get-Item $(Get-Location)).Parent.FullName
}