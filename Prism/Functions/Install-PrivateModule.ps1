
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
        $privateModulePathWildcard = Join-Path -Path $installDirPath -ChildPath '*'
        $locks = Get-Content -Path $Configuration.LockPath | ConvertFrom-Json
        $locks | Add-Member -Name 'PSModules' -MemberType NoteProperty -Value @() -ErrorAction Ignore

        if ($Name)
        {
            $locks.PSModules = $locks.PSModules | Where-Object {$_.Name -in $Name}
        }

        foreach ($module in $locks.PSModules)
        {
            $installedModules =
                Get-Module -Name $module.name -ListAvailable -ErrorAction Ignore |
                Where-Object 'Path' -Like $privateModulePathWildcard |
                Add-Member -Name 'SemVer' -MemberType ScriptProperty -PassThru -Value {
                    $prerelease = $this.PrivateData['PSData']['PreRelease']
                    if ($prerelease)
                    {
                        $prerelease = "-$($prerelease)"
                    }
                    return "$($this.Version)$($prerelease)"
                }

            $installedModule = $installedModules | Where-Object 'SemVer' -EQ $module.version
            if ($installedModule)
            {
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
                Write-Error $msg
                continue
            }

            if (-not (Test-Path -Path $installDirPath))
            {
                New-Item -Path $installDirPath -ItemType 'Directory' -Force | Out-Null
            }

            Save-Module -Name $module.name `
                        -Path $installDirPath `
                        -RequiredVersion $module.version `
                        -AllowPrerelease `
                        -Repository $repoName `
                        @pkgMgmtPrefs

            # How many versions of this module will we be installing?
            $moduleVersionCount = ($locks.PSModules | Where-Object 'Name' -EQ $module.name | Measure-Object).Count

            # PowerShell has a 10 directory limit for nested modules, so reduce the number of nested directories
            # when installing a nested module by installing directly in the module root directory and moving
            # everything out of the version module directory.
            if ($Configuration.Nested -and $moduleVersionCount -eq 1)
            {
                $modulePath = Join-Path -Path $installDirPath -ChildPath $module.name
                $versionDirName = $module.version
                if ($versionDirName -match '^(\d+\.\d+\.\d+)')
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