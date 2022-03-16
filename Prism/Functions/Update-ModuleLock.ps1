
function Update-ModuleLock
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Configuration
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
        if( -not $moduleNames )
        {
            Write-Warning "There are no modules listed in ""$($Path | Resolve-Path -Relative)""."
            return
        }

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
            if( -not $modules )
            {
                $msg = "$($Path | Resolve-Path -Relative): Modules ""$($uniqueModuleNames -join '", "')"" not " +
                       'found.'
                Write-Error $msg
                return
            }

            # Find-Module is expensive. Limit calls as much as possible.
            $findModuleCache = @{}

            $locks = [Collections.ArrayList]::New()

            $env:PSModulePath =
                Join-Path -Path $Configuration.File.DirectoryName -ChildPath $Configuration.PSModulesDirectoryName
            foreach( $pxModule in $Configuration.PSModules )
            {
                $optionalParams = @{}

                # Make sure these members are present and have default values.
                $pxModule | Add-Member -Name 'Version' -MemberType NoteProperty -Value '' -ErrorAction Ignore
                $pxModule |
                    Add-Member -Name 'AllowPrerelease' -MemberType NoteProperty -Value $false -ErrorAction Ignore

                $versionDesc = 'latest'
                if( $pxModule.Version )
                {
                    $versionDesc = $optionalParams['Version'] = $pxModule.Version
                }

                $allowPrerelease = $false
                if( $pxModule.AllowPrerelease -or $pxModule.Version -match '-' )
                {
                    $allowPrerelease = $optionalParams['AllowPrerelease'] = $true
                }

                $curStep += 1

                Write-Debug "  curStep   $($curStep)"
                $moduleToInstall =
                    $modules | Select-Module -Name $pxModule.Name @optionalParams | Select-Object -First 1
                if( -not $moduleToInstall )
                {
                    $status = "Find-Module -Name '$($pxModule.Name)' -AllVersions"
                    if( $allowPrerelease )
                    {
                        $status = "$($status) -AllowPrerelease"
                    }

                    if( -not $findModuleCache.ContainsKey($status) )
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

                if( -not $moduleToInstall )
                {
                    [void]$modulesNotFound.Add($pxModule.Name)
                    continue
                }

                $pin = [pscustomobject]@{
                    name = $moduleToInstall.Name;
                    version = $moduleToInstall.Version;
                    location = $moduleToInstall.RepositorySourceLocation;
                }
                [void]$locks.Add( $pin )
                [pscustomobject]@{
                    'ModuleName' = $pxModule.Name;
                    'Version' = $versionDesc;
                    'LockedVersion' = $pin.version;
                    'Location' = $pin.location;
                } | Write-Output
            }

            Write-Progress @activity -Status "Saving lock file ""$($Configuration.LockPath)""." -PercentComplete 100
            $prismLock = [pscustomobject]@{
                PSModules = $locks;
            }
            $prismLock | ConvertTo-Json -Depth 2 | Set-Content -Path $Configuration.LockPath -NoNewline

            if( $modulesNotFound.Count )
            {
                $suffix = ''
                if( $modulesNotFound.Count -gt 1 )
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