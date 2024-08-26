
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

        [Collections.Generic.List[String]]$nameCopy = $Name
        foreach ($item in $Name)
        {
            if ($item -notin $moduleNames)
            {
                Write-Warning "The given module ""$item"" does not exist in the prism.json file."
                $nameCopy.Remove($item)
            }
        }

        if ($Name -and -not $nameCopy)
        {
            return
        }
        $Name = $nameCopy

        $numFinds = $moduleNames | Measure-Object | Select-Object -ExpandProperty 'Count'
        $numFinds = $numFinds + 2
        Write-Debug "  numSteps  $($numFinds)"
        $curStep = 0
        $uniqueModuleNames = $moduleNames | Select-Object -Unique
        $status = "Find-Module -Name '$($uniqueModuleNames -join "', '")'"
        $percentComplete = ($curStep++/$numFinds * 100)
        $activity = @{ Activity = 'Resolving Module Versions' }
        Write-Progress @activity -Status $status -PercentComplete $percentComplete

        try
        {
            $modules = Find-Module -Name $uniqueModuleNames -ErrorAction Ignore @pkgMgmtPrefs

            # Find-Module is expensive. Limit calls as much as possible.
            $findModuleCache = @{}

            $locks = [Collections.ArrayList]::New()

            $env:PSModulePath =
                Join-Path -Path $Configuration.File.DirectoryName -ChildPath $Configuration.PSModulesDirectoryName
            foreach( $pxModule in $Configuration.PSModules )
            {
                $currentLock = $null
                if ($Name)
                {
                    if ($Configuration.LockPath -and (Test-Path -Path $Configuration.LockPath))
                    {
                        $currentLock = Get-Content -Path $Configuration.LockPath | ConvertFrom-Json
                    }
    
                    # If current module is not in the given list of modules and doesn't already exist in the lock file, skip.
                    if ($currentLock -and ($pxModule.Name -notin $Name) -and ($pxModule.Name -notin $currentLock.PSModules.Name))
                    {
                        continue
                    }
                }
                
                $optionalParams = @{}

                # Make sure these members are present and have default values.
                $pxModule | Add-Member -Name 'Version' -MemberType NoteProperty -Value '' -ErrorAction Ignore
                $pxModule |
                    Add-Member -Name 'AllowPrerelease' -MemberType NoteProperty -Value $false -ErrorAction Ignore

                $versionDesc = 'latest'
                if ($pxModule.Version)
                {
                    $versionDesc = $optionalParams['Version'] = $pxModule.Version

                    # If current module is not in the given list of modules, use it's version from lock file.
                    if ($Name -and $pxModule.Name -notin $Name)
                    {
                        $lockedModule = $currentLock.PSModules | Where-Object {$_.Name -eq $pxModule.Name}
                        $versionDesc = $optionalParams['Version'] = $lockedModule.Version
                    }
                }

                $allowPrerelease = $false
                if ($pxModule.AllowPrerelease -or $pxModule.Version -match '-')
                {
                    $allowPrerelease = $optionalParams['AllowPrerelease'] = $true
                }

                $curStep += 1

                Write-Debug "  curStep   $($curStep)"
                $moduleToInstall =
                    $modules | Select-Module -Name $pxModule.Name @optionalParams | Select-Object -First 1
                if (-not $moduleToInstall)
                {
                    $status = "Find-Module -Name '$($pxModule.Name)' -AllVersions"
                    if ($allowPrerelease)
                    {
                        $status = "$($status) -AllowPrerelease"
                    }

                    if (-not $findModuleCache.ContainsKey($status))
                    {
                        Write-Progress @activity -Status $status -PercentComplete ($curStep/$numFinds * 100)
                        $findModuleCache[$status] = Find-Module -Name $pxModule.Name `
                                                                -AllVersions `
                                                                -AllowPrerelease:$allowPrerelease `
                                                                -ErrorAction Ignore `
                                                                @pkgMgmtPrefs
                    }
                    $moduleToInstall =
                        $findModuleCache[$status] |
                        Select-Module -Name $pxModule.Name @optionalParams |
                        Select-Object -First 1
                }

                if (-not $moduleToInstall)
                {
                    [void]$modulesNotFound.Add($pxModule.Name)
                    continue
                }

                $pin = [pscustomobject]@{
                    name = $moduleToInstall.Name;
                    version = $moduleToInstall.Version;
                    repositorySourceLocation = $moduleToInstall.RepositorySourceLocation;
                }
                [void]$locks.Add( $pin )

                if (-not (Test-Path -Path $Configuration.LockPath))
                {
                    New-Item -Path $Configuration.LockPath `
                             -ItemType 'File' `
                             -Value (([pscustomobject]@{}) | ConvertTo-Json) |
                        Out-Null
                }

                $moduleLock = [pscustomobject]@{
                    ModuleName = $pxModule.Name;
                    Version = $versionDesc;
                    LockedVersion = $pin.version;
                    RepositorySourceLocation = $pin.repositorySourceLocation;
                    Path = ($Configuration.LockPath | Resolve-Path -Relative);
                }
                $moduleLock.pstypenames.Add('Prism.ModuleLock')
                $moduleLock | Write-Output
            }

            Write-Progress @activity -Status "Saving lock file ""$($Configuration.LockPath)""." -PercentComplete 100
            $prismLock = [pscustomobject]@{
                PSModules = $locks;
            }
            $prismLock | ConvertTo-Json -Depth 2 | Set-Content -Path $Configuration.LockPath -NoNewline

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