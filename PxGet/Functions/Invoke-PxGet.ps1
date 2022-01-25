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

    $origModulePath = $env:PSModulePath
    $privateModulesPath = Join-Path -Path $(Get-Location) -ChildPath 'PSModules'
    if( -not (Test-Path -Path $privateModulesPath) )
    {
        New-Item -Path $privateModulesPath -ItemType 'Directory' | Out-Null
    }

    $deepPrefs = @{}

    if( (Test-Path -Path 'env:PXGET_DISABLE_DEEP_DEBUG') )
    {
        $deepPrefs['Debug'] = $false
    }

    if( (Test-Path -Path 'env:PXGET_DISABLE_DEEP_VERBOSE') )
    {
        $deepPrefs['Verbose'] = $false
    }

    $activity = 'pxget install'
    try
    {
        # pxget should ship with its own private copies of PackageManagement and PowerShellGet. Setting PSModulePath
        # to pxget module's Modules directory ensures no other package modules get loaded.
        $pxGetModulesRoot = Join-Path -Path $moduleRoot -ChildPath 'Modules'
        $env:PSModulePath = $pxGetModulesRoot
        Write-Debug "PSModulePath  $($env:PSModulePath)"
        Write-Debug "moduleRoot    $($pxGetModulesRoot)"
        Get-Module -ListAvailable | Format-Table -AutoSize | Out-String | Write-Debug
        Import-Module -Name 'PackageManagement' @deepPrefs
        Import-Module -Name 'PowerShellGet' @deepPrefs
        Get-Module | Format-Table -AutoSize | Out-String | Write-Debug

        $env:PSModulePath = @($privateModulesPath, $pxGetModulesRoot) -join [IO.Path]::PathSeparator
        Write-Debug "PSModulePath  $($env:PSModulePath)"
        Get-Module -ListAvailable | Format-Table -AutoSize | Out-String | Write-Debug

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

        $numInstalls = $moduleNames | Measure-Object | Select-Object -ExpandProperty 'Count'
        $numInstalls = $numInstalls * 2 + 1
        Write-Debug "  numSteps  $($numInstalls)"
        $curStep = 0
        $status = 'Finding latest module versions.'
        $uniqueModuleNames = $moduleNames | Select-Object -Unique
        $op = "Find-Module -Name '$($uniqueModuleNames -join "', '")'"
        $percentComplete = ($curStep++/$numInstalls * 100)
        Write-Progress -Activity $activity -Status $status -CurrentOperation $op -PercentComplete $percentComplete

        $modules = Find-Module -Name $uniqueModuleNames -ErrorAction Ignore @deepPrefs
        if( -not $modules )
        {
            $msg = "$($pxgetJsonPath | Resolve-Path -Relative): Modules ""$($uniqueModuleNames -join '", "')"" not " +
                   'found.'
            Write-Error $msg
            return
        }

        # Find-Module is expensive. Limit calls as much as possible.
        $findModuleCache = @{}

        # We only care if the module is in PSModules right now. Later we'll allow dev dependencies, which can be
        # installed globally.
        $env:PSModulePath = $privateModulesPath
        foreach( $pxModule in $pxModules.PSModules )
        {
            $allowPrerelease = $pxModule.Version -match '-'

            $progressState = @{
                Activity = $activity;
                Status = "Saving $($pxModule.Name) $($pxModule.Version)";
            }

            Write-Debug "  curStep   $($curStep)"
            $percentComplete = ($curStep++/$numInstalls * 100)
            $moduleToInstall =
                $modules |
                Select-Module -Name $pxModule.Name -Version $pxModule.Version -AllowPrerelease:$allowPrerelease |
                Select-Object -First 1
            if( -not $moduleToInstall )
            {
                $allowPrereleaseOp = ''
                if( $allowPrerelease )
                {
                    $allowPrereleaseOp = ' -AllowPrerelease'
                }
                $op = "Find-Module -Name '$($pxModule.Name)' -AllVersions$($allowPrereleaseOp)"
                if( -not $findModuleCache.ContainsKey($op) )
                {
                    Write-Progress @progressState -CurrentOperation $op -PercentComplete $percentComplete
                    $findModuleCache[$op] = Find-Module -Name $pxModule.Name `
                                                        -AllVersions `
                                                        -AllowPrerelease:$allowPrerelease `
                                                        -ErrorAction Ignore `
                                                        @deepPrefs
                }
                $moduleToInstall =
                    $findModuleCache[$op] |
                    Select-Module -Name $pxModule.Name -Version $pxModule.Version -AllowPrerelease:$allowPrerelease |
                    Select-Object -First 1
            }

            if( -not $moduleToInstall )
            {
                Write-Debug "  curStep   $($curStep)"
                $curStep += 1
                $modulesNotFound += $pxModule.Name
                continue
            }

            $progressState['Status'] = "Saving $($moduleToInstall.Name) $($moduleToInstall.Version)"
            Write-Progress @progressState -PercentComplete $percentComplete
            Start-Sleep -Seconds 2

            $installedModule =
                Get-Module -Name $pxModule.Name -List |
                Where-Object 'Version' -eq $moduleToInstall.Version
            # The latest version that matches the version in the pxget.json file is already installed
            if( $installedModule )
            {
                Write-Debug "  curStep   $($curStep)"
                $curStep += 1

                $installedModule
                continue
            }

            $installPath = $privateModulesPath
            if( ($pxModule.PSObject.Properties.Name -Contains 'Path') -and (-not [string]::IsNullOrWhiteSpace($pxModule.Path)) )
            {
                $installPath = $pxModule.Path
            }

            if( -not (Test-Path -Path $installPath) )
            {
                New-Item -Path $installPath -ItemType 'Directory' | Out-Null
            }

            $op = "Save-Module -Name '$($moduleToInstall.Name)' -Version '$($moduleToInstall.Version)' -Path " +
                  "'$($installPath | Resolve-Path -Relative)' -Repository '$($moduleToInstall.Repository)'"
            Write-Debug "  curStep   $($curStep)"
            $percentComplete = ($curStep++/$numInstalls * 100)
            Write-Progress @progressState -CurrentOperation $op -PercentComplete $percentComplete
            $curProgressPref = $ProgressPreference
            $Global:ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
            try
            {
                # Not installed. Install it. We pipe it so the repository of the module is also used.
                $moduleToInstall | Save-Module -Path $installPath @deepPrefs
            }
            finally
            {
                $Global:ProgressPreference = $curProgressPref
            }

            $savedToPath = Join-Path -Path $installPath -ChildPath $moduleToInstall.Name
            $savedToPath = Join-Path -Path $savedToPath -ChildPath ($moduleToInstall.Version -replace '-.*$', '')
            Get-Module -Name $savedToPath -ListAvailable @deepPrefs
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
        Write-Progress -Activity $activity -Completed
    }
}

Set-Alias -Name 'pxget' -Value 'Invoke-PxGet'
