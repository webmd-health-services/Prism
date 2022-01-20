function Invoke-PxGet
{
    <#
    .SYNOPSIS
    Invokes PxGet.
    
    .DESCRIPTION
    A tool similar to nuget but for PowerShell modules. A config file in the root of a repository that specifies 
    what modules should be installed into the PSModules directory of the repository. If a path is provided for the
    module it will be installed at the specified path instead of the PSModules directory.

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
        $pxgetJsonPath = Join-Path -Path (Get-Location) -ChildPath 'pxget.json'

        if( -not (Test-Path -Path $pxgetJsonPath) )
        {
            Write-Error 'There is no pxget.json file in the current directory.'
            return
        }

        $pxModules = Get-Content -Path $pxgetJsonPath | ConvertFrom-Json
        if( -not $pxModules )
        {
            Write-Warning 'The pxget.json file is empty!'
            return
        }

        $moduleNames = $pxModules.PSModules | Select-Object -ExpandProperty 'Name'
        if( -not $moduleNames )
        {
            Write-Warning "There are no modules listed in ""$($pxgetJsonPath | Resolve-Path -Relative)""."
            return
        }
        
        $modules = Find-Module -Name $moduleNames -ErrorAction Ignore
        if( -not $modules )
        {
            Write-Error "$($pxgetJsonPath | Resolve-Path -Relative): Modules ""$($moduleNames -join '", "')"" not found."
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
                if( -not $moduleToInstall )
                {
                    $moduleWithAllVersions = Find-Module -Name $pxModule.Name -AllVersions -ErrorAction Ignore
                    $moduleToInstall = $moduleWithAllVersions | Select-Module -Name $pxModule.name -Version $pxModule.Version | Select-Object -First 1
                }
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

            $installPath = $psmodulesPath
            if( ($pxModule.PSObject.Properties.Name -Contains 'Path') -and (-not [string]::IsNullOrWhiteSpace($pxModule.Path)) )
            {
                $installPath = $pxModule.Path
            }

            if( -not (Test-Path -Path $installPath) )
            {
                New-Item -Path $installPath -ItemType 'Directory' | Out-Null
            }

            # Not installed. Install it. We pipe it so the repository of the module is also used.
            $moduleToInstall | Save-Module -Path $installPath
            $savedToPath = Join-Path -Path $installPath -ChildPath $moduleToInstall.Name
            $savedToPath = Join-Path -Path $savedToPath -ChildPath ($moduleToInstall.Version -replace '-.*$', '')
            Get-Module -Name $savedToPath -ListAvailable
        }
        if( $modulesNotFound )
        {
            Write-Error "$($pxgetJsonPath | Resolve-Path -Relative): Module(s) ""$($modulesNotFound -join '", "')"" not found."
            return
        }
    }
    finally
    {
        $env:PSModulePath = $origModulePath
    }
}

Set-Alias -Name 'pxget' -Value 'Invoke-PxGet'
