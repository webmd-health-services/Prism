
# Ugh. I hate this name, but it interferes with Install-Module in one of the package management modules.
function Install-PrivateModule
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
        if( -not (Test-Path -Path $Configuration.LockPath) )
        {
            $Configuration | Update-ModuleLock | Format-Table
        }

        $repoByLocation = @{}
        Get-PSRepository |
            ForEach-Object {
                $repoUrl = $_.SourceLocation
                $repoByLocation[$repoUrl] = $_.Name

                # Ignore slashes at the end of URLs.
                $trimmedRepoUrl = $repoUrl.TrimEnd('/')
                $repoByLocation[$trimmedRepoUrl] = $_.Name
            }

        $locks = Get-Content -Path $Configuration.LockPath | ConvertFrom-Json
        $locks | Add-Member -Name 'PSModules' -MemberType NoteProperty -Value @() -ErrorAction Ignore
        foreach( $module in $locks.PSModules )
        {
            $installedModules =
                Get-Module -Name $module.name -ListAvailable -ErrorAction Ignore |
                Add-Member -Name 'SemVer' -MemberType ScriptProperty -PassThru -Value {
                    $prerelease = $this.PrivateData['PSData']['PreRelease']
                    if( $prerelease )
                    {
                        $prerelease = "-$($prerelease)"
                    }
                    return "$($this.Version)$($prerelease)"
                }

            $savePath =
                Join-Path -Path $Configuration.File.DirectoryName -ChildPath $Configuration.PSModulesDirectoryName

            $installedModule = $installedModules | Where-Object SemVer -EQ $module.version 
            if( -not $installedModule )
            {
                $sourceUrl = $module.repositorySourceLocation
                $repoName = $repoByLocation[$sourceUrl]
                if( -not $repoName )
                {
                    # Ignore slashes at the end of URLs.
                    $sourceUrl = $sourceUrl.TrimEnd('/')
                }
                $repoName = $repoByLocation[$sourceUrl]
                if( -not $repoName )
                {
                    $msg = "PowerShell repository at ""$($module.repositorySourceLocation)"" does not exist. Use " +
                            '"Get-PSRepository" to see the current list of repositories, "Register-PSRepository" ' +
                            'to add a new repository, or "Set-PSRepository" to update an existing repository.'
                    Write-Error $msg
                    continue
                }

                if( -not (Test-Path -Path $savePath) )
                {
                    New-Item -Path $savePath -ItemType 'Directory' -Force | Out-Null
                }

                Save-Module -Name $module.name `
                            -Path $savePath `
                            -RequiredVersion $module.version `
                            -AllowPrerelease `
                            -Repository $repoName `
                            @pkgMgmtPrefs
            }

            $modulePath = Join-Path -Path $savePath -ChildPath $module.name | Resolve-Path -Relative
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