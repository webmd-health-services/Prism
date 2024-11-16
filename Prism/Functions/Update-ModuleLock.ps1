
function Update-ModuleLock
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Configuration,

        # A subset of the required modules to install or update.
        [String[]] $Name
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $pkgMgmtPrefs = Get-PackageManagementPreference
    }

    process
    {
        $modulesNotFound = [Collections.ArrayList]::New()
        $moduleNames = $Configuration.PSModules | Select-Object -ExpandProperty 'Name'
        if (-not $moduleNames)
        {
            Write-Warning "There are no modules listed in ""$($Configuration.Path | Resolve-Path -Relative)""."
            return
        }

        $numFinds = $moduleNames | Measure-Object | Select-Object -ExpandProperty 'Count'
        $numFinds = $numFinds + 2
        Write-Debug "  numSteps  $($numFinds)"
        $curStep = 0
        $uniqueModuleNames =
            $moduleNames |
            Select-Object -Unique |
            Where-Object {
                if (-not $Name)
                {
                    return $true
                }

                $moduleName = $_
                return $Name | Where-Object { $moduleName -like $_ }
            }

        if (-not $uniqueModuleNames)
        {
            return
        }

        $status = "Find-Module -Name '$($uniqueModuleNames -join "', '")'"
        $percentComplete = ($curStep++/$numFinds * 100)
        $activity = @{ Activity = 'Resolving Module Versions' }
        Write-Progress @activity -Status $status -PercentComplete $percentComplete

        $currentLocks = [pscustomobject]@{
            'PSModules' = @()
        }

        $lockDisplayPath = $Configuration.LockPath
        if ($Configuration.LockPath -and (Test-Path -Path $Configuration.LockPath))
        {
            $numErrors = $Global:Error.Count
            try
            {
                $currentLocks = Get-Content -Path $Configuration.LockPath | ConvertFrom-Json -ErrorAction Ignore
            }
            catch
            {
                $numErrorsToDelete = $Global:Error.Count - $numErrors
                for ($idx = 0 ; $idx -lt $numErrorsToDelete; ++$idx)
                {
                    $Global:Error.RemoveAt(0)
                }
            }

            $lockDisplayPath = $lockDisplayPath | Resolve-Path -Relative
        }

        try
        {
            $modules = Find-Module -Name $uniqueModuleNames -ErrorAction Ignore @pkgMgmtPrefs

            # Find-Module is expensive. Limit calls as much as possible.
            $findModuleCache = @{}

            $env:PSModulePath =
                Join-Path -Path $Configuration.File.DirectoryName -ChildPath $Configuration.PSModulesDirectoryName

            $locksUpdated = $false

            foreach ($module in $Configuration.PSModules)
            {
                if ($Name -and -not ($Name | Where-Object { $module.Name -like $_ }))
                {
                    continue
                }

                $optionalParams = @{}

                # Make sure these members are present and have default values.
                $module | Add-Member -Name 'Version' -MemberType NoteProperty -Value '' -ErrorAction Ignore
                $module |
                    Add-Member -Name 'AllowPrerelease' -MemberType NoteProperty -Value $false -ErrorAction Ignore

                $versionDesc = 'latest'
                if ($module.Version)
                {
                    $versionDesc = $optionalParams['Version'] = $module.Version
                }

                $allowPrerelease = $false
                if ($module.AllowPrerelease -or $module.Version -match '-|\+')
                {
                    $allowPrerelease = $optionalParams['AllowPrerelease'] = $true
                }

                $curStep += 1

                Write-Debug "  curStep   $($curStep)"
                $moduleToInstall =
                    $modules | Select-Module -Name $module.Name @optionalParams | Select-Object -First 1
                if (-not $moduleToInstall)
                {
                    $status = "Find-Module -Name '$($module.Name)' -AllVersions"
                    if ($allowPrerelease)
                    {
                        $status = "$($status) -AllowPrerelease"
                    }

                    if (-not $findModuleCache.ContainsKey($status))
                    {
                        Write-Progress @activity -Status $status -PercentComplete ($curStep/$numFinds * 100)
                        $findModuleCache[$status] = Find-Module -Name $module.Name `
                                                                -AllVersions `
                                                                -AllowPrerelease:$allowPrerelease `
                                                                -ErrorAction Ignore `
                                                                @pkgMgmtPrefs
                    }
                    $moduleToInstall =
                        $findModuleCache[$status] |
                        Select-Module -Name $module.Name @optionalParams |
                        Select-Object -First 1
                }

                if (-not $moduleToInstall)
                {
                    [void]$modulesNotFound.Add($module.Name)
                    continue
                }

                $lockUpdated = $false
                $oldVersion = ''

                $lock = $currentLocks.PSModules | Where-Object 'name' -eq $moduleToInstall.name
                if ($lock)
                {
                    $oldVersion = $lock.version
                }
                else
                {
                    $lock = [pscustomobject]@{
                        name = $moduleToInstall.Name;
                        version = $moduleToInstall.Version;
                        repositorySourceLocation = $moduleToInstall.RepositorySourceLocation;
                    }
                    $currentLocks.PSModules += $lock
                    $lockUpdated = $true
                }

                if ($moduleToInstall.Version -ne $lock.version)
                {
                    $lock.version = $moduleToInstall.Version
                    $lockUpdated = $true
                }

                if (-not $lockUpdated)
                {
                    continue
                }

                $locksUpdated = $lockUpdated

                $moduleLock = [pscustomobject]@{
                    ModuleName = $lock.Name;
                    Version = $versionDesc;
                    PreviousLockedVersion = $oldVersion;
                    LockedVersion = $lock.version;
                    RepositorySourceLocation = $lock.repositorySourceLocation;
                    Path = $lockDisplayPath;
                }
                $moduleLock.pstypenames.Add('Prism.ModuleLock')
                $moduleLock | Write-Output
            }

            if ($locksUpdated)
            {
                Write-Progress @activity -Status "Saving lock file ""$($Configuration.LockPath)""." -PercentComplete 100
                [Object[]] $sortedPSModules = $currentLocks.PSModules | Sort-Object -Property 'Name','Version'
                $currentLocks.PSModules = $sortedPSModules
                $currentLocks | ConvertTo-Json -Depth 2 | Set-Content -Path $Configuration.LockPath -NoNewline
            }

            if ($modulesNotFound.Count)
            {
                $suffix = ''
                if ($modulesNotFound.Count -gt 1)
                {
                    $suffix = 's'
                }
                $msg = "$($Path | Resolve-Path -Relative): Module$($suffix) ""$($modulesNotFound -join '", "')"" not " +
                       'found.'
                Write-Error $msg
            }
        }
        finally
        {
            Write-Progress @activity -Completed
        }
    }
}