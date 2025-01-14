
# Ugh. I hate this name, but it interferes with Install-Module in one of the package management modules.
function Install-PrivateModule
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

        $repoByLocation = @{}
        foreach ($repo in (Get-PSRepository))
        {
            $repoUrl = $repo.SourceLocation
            $repoByLocation[$repoUrl] = $repo.Name

            # Ignore slashes at the end of URLs.
            $trimmedRepoUrl = $repoUrl.TrimEnd('/')
            $repoByLocation[$trimmedRepoUrl] = $repo.Name
        }
    }

    process
    {
        if (-not (Test-Path -Path $Configuration.LockPath))
        {
            $Configuration | Update-ModuleLock | Out-Null
        }

        $installDirPath = $Configuration.InstallDirectoryPath
        $locks = Get-Content -Path $Configuration.LockPath | ConvertFrom-Json
        $locks | Add-Member -Name 'PSModules' -MemberType NoteProperty -Value @() -ErrorAction Ignore

        if ($Name)
        {
            $locks.PSModules = $locks.PSModules | Where-Object {$_.Name -in $Name}
        }

        $installedModules =
            & {
                    $origPSModulePath = $env:PSModulePath
                    $env:PSModulePath = $Configuration.InstallDirectoryPath
                    try
                    {
                        Write-Debug $env:PSModulePath
                        Get-Module -ListAvailable -ErrorAction Ignore
                    }
                    finally
                    {
                        $env:PSModulePath = $origPSModulePath
                    }
            } |
            Add-Member -Name 'SemVer' -MemberType ScriptProperty -PassThru -Value {
                $prerelease = $this.PrivateData['PSData']['PreRelease']
                if ($prerelease)
                {
                    $prerelease = "-$($prerelease)"
                }
                return "$($this.Version)$($prerelease)"
            }

            $installedModules | Format-Table -Auto | Out-String | Write-Debug

        foreach ($module in $locks.PSModules)
        {
            $module | Format-List | Out-String | Write-Debug
            $installedModule =
                $installedModules | Where-Object 'Name' -EQ $module.Name | Where-Object 'SemVer' -EQ $module.version
            if ($installedModule)
            {
                Write-Debug 'Module already installed.'
                continue
            }

            $sourceUrl = $module.repositorySourceLocation
            $repoName = $repoByLocation[$sourceUrl]
            if (-not $repoName)
            {
                # Ignore slashes at the end of URLs.
                $sourceUrl = $sourceUrl.TrimEnd('/')
            }
            $repoName = $repoByLocation[$sourceUrl]
            if (-not $repoName)
            {
                $msg = "PowerShell repository at ""$($module.repositorySourceLocation)"" does not exist. Use " +
                       '"Get-PSRepository" to see the current list of repositories, "Register-PSRepository" ' +
                       'to add a new repository, or "Set-PSRepository" to update an existing repository.'
                Write-Debug "Unknown repo."
                Write-Error $msg
                continue
            }

            if (-not (Test-Path -Path $installDirPath))
            {
                New-Item -Path $installDirPath -ItemType 'Directory' -Force | Out-Null
            }

            # How many versions of this module will we be installing?
            $moduleVersionCount = ($locks.PSModules | Where-Object 'Name' -EQ $module.name | Measure-Object).Count

            $singleVersion = $moduleVersionCount -eq 1
            Write-Debug "Nested               $($Configuration.Nested)"
            Write-Debug "moduleVersionCount   ${moduleVersionCount}"
            Write-Debug "singleVersion  ${singleVersion}"

            $moduleDirPath = Join-Path -Path $installDirPath -ChildPath $module.Name
            Write-Debug "moduleDirPath        ${moduleDirPath}"
            if ($singleVersion -and $Configuration.FlattenModules -and (Test-Path -Path $moduleDirPath))
            {
                Write-Debug "Removing ${moduleDirPath}"
                Remove-Item -Path $moduleDirPath -Recurse -Force
                if (Test-Path -Path $moduleDirPath)
                {
                    $msg = "Failed to save PowerShell module ""$($module.name)"" $($module.version) to " +
                           "destination ""${moduleDirPath}"" because that destination already exists and deletion " +
                           'failed.'
                    Write-Debug "Failed to delete module."
                    Write-Error -Message $msg -ErrorAction $ErrorActionPreference
                    continue
                }
            }

            Save-Module -Name $module.name `
                        -Path $installDirPath `
                        -RequiredVersion $module.version `
                        -AllowPrerelease `
                        -Repository $repoName `
                        @pkgMgmtPrefs

            # Windows has a 260 character limit for path length. Reduce paths by removing extraneous version
            # directories.
            if ($singleVersion -and $Configuration.FlattenModules)
            {
                $modulePath = Join-Path -Path $installDirPath -ChildPath $module.name
                $versionDirName = $module.version
                if ($versionDirName -match '^(\d+\.\d+\.\d+(?:\.\d+)?)')
                {
                    $versionDirName = $Matches[1]
                }
                $moduleVersionPath = Join-Path -Path $modulePath -ChildPath $versionDirName
                Get-ChildItem -Path $moduleVersionPath -Force | Move-Item -Destination $modulePath
                Get-Item -Path $moduleVersionPath | Remove-Item
            }

            $modulePath = Join-Path -Path $installDirPath -ChildPath $module.name | Resolve-Path -Relative
            $installedModule = [pscustomobject]@{
                Name = $module.name;
                Version = $module.version;
                Path = $modulePath;
                RepositorySourceLocation = $module.repositorySourceLocation;
            }
            $installedModule.pstypenames.Add('Prism.InstalledModule')
            $installedModule | Write-Output
        }
    }
}