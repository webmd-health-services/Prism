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
        [string] $Command
    )
 
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $DebugPreference = 'Continue'

    $origModulePath = $env:PSModulePath
    $psmodulesPath = Join-Path -Path $(Get-Location) -ChildPath 'PSModules'
    if( -not (Test-Path -Path $psmodulesPath) )
    {
        New-Item -Path $psmodulesPath -ItemType 'Directory' | Out-Null
    }
    
    try
    {
        # pxget should ship with its own private copies of PackageManagement and PowerShellGet. Setting PSModulePath
        # to pxget module's Modules directory ensures no other package modules get loaded.
        $env:PSModulePath = $psmodulesPath
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'Modules\PackageManagement')
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'Modules\PowerShellGet')
        $modulesNotFound = @()

        if( -not (Test-Path -Path (Join-Path -Path (Get-Location) -ChildPath 'pxget.json')) )
        {
            Write-Error 'There is no pxget.json file in the current directory.'
            return
        }

        $pxModules = Get-Content -Path ($(Get-Location) + '\pxget.json') | ConvertFrom-Json
        if( -not $pxModules )
        {
            Write-Warning 'The pxget.json file is empty!'
            return
        }

        $moduleNames = $pxModules.PSModules | Select-Object -ExpandProperty 'Name'
        if( -not $moduleNames )
        {
            Write-Warning 'There are no modules listed in the pxget.json file!'
            return
        }
        
        $modules = Find-Module -Name $moduleNames -ErrorAction Ignore
        if( -not $modules )
        {
            Write-Error 'No modules were found using the module names from the pxget file!'
            return
        }

        # We only care if the module is in PSModules right now. Later we'll allow dev dependencies, which can be
        # installed globally.
        $env:PSModulePath = $psModulesPath
        foreach( $pxModule in $pxModules.PSModules )
        {
            $allowPrerelease = $pxModule.Version.Contains('-')
            
            if( $allowPrerelease)
            {
                # Find module again but with AllVersions and AllowPrerelease
                $modulesWithPrelease = Find-Module -Name $pxModule.Name -AllowPrerelease -AllVersions
                $moduleToInstall = $modulesWithPrelease | Select-Module -Name $pxModule.Name -Version $pxModule.Version -AllowPrerelease | Select-Object -First 1
            }
            else
            {
                $moduleToInstall = $modules | Select-Module -Name $pxModule.Name -Version $pxModule.Version | Select-Object -First 1
            }

            if( -not $moduleToInstall )
            {
                $modulesNotFound += $pxModule.Name
                continue
            }

            $installedModule =
                Get-Module -Name $pxModule.Name -List |
                Where-Object 'Version' -eq $moduleToInstall.Version
            # The latest version that matches the version in the pxget.json file is already installed
            if( $installedModule )
            {
                continue
            }

            # Not installed. Install it. We pipe it so the repository of the module is also used.
            $moduleToInstall | Save-Module -Path $psmodulesPath
            $savedToPath = Join-Path -Path $psmodulesPath -ChildPath $moduleToInstall.Name
            $savedToPath = Join-Path -Path $savedToPath -ChildPath ($moduleToInstall.Version -replace '-.*$', '')
            Get-Module -Name $savedToPath -ListAvailable
        }
        if( $modulesNotFound )
        {
            Write-Error "The following modules were not found: $($modulesNotFound -join ', ')"
            return
        }
    }
    finally
    {
        $env:PSModulePath = $origModulePath
    }
}

Set-Alias -Name 'pxget' -Value 'Invoke-PxGet'
