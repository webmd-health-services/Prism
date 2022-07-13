function Invoke-Prism
{
    <#
    .SYNOPSIS
    Invokes Prism.

    .DESCRIPTION
    A tool similar to nuget but for PowerShell modules. A config file in the root of a repository that specifies
    what modules should be installed into the PSModules directory of the repository. If a path is provided for the
    module it will be installed at the specified path instead of the PSModules directory.

    .EXAMPLE
    Invoke-Prism 'install'

    Demonstrates how to call this function to install required PSModules.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('install', 'update')]
        [String] $Command,

        # The path to a prism.json file or a directory where Prism can find a prism.json file. If path is to a file,
        # the "FileName" parameter is ignored, if given.
        #
        # If the path is a directory, Prism will look for a "prism.json' file in that directory. If the -Recurse switch
        # is given and the path is to a directory, Prism will recursively search in and under that directory and run for
        # each prism.json file it finds. If Path is to a directory and FileName is given, Prism will look for a file
        # with that name instead.
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [String] $Path,

        # The name of the Prism configuration file to use. Defaults to `prism.json`. Ignored if "Path" is given and is
        # the path to a file.
        [String] $FileName = 'prism.json',

        # If given, searches the current directory and all sub-directories for prism.json files and runs the command
        # for each file. If the Path parameter is given and is to a directory, Prism will start searching in that
        # directory instead of the current directory.
        [switch] $Recurse
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState    

        $origModulePath = $env:PSModulePath

        $pkgMgmtPrefs = Get-PackageManagementPreference

        Import-Module -Name 'PackageManagement' `
                      -MinimumVersion '1.3.2' `
                      -MaximumVersion '1.4.7' `
                      -Global `
                      -ErrorAction Stop `
                      @pkgMgmtPrefs
        Import-Module -Name 'PowerShellGet' `
                      -MinimumVersion '2.0.0' `
                      -MaximumVersion '2.2.5' `
                      -Global `
                      -ErrorAction Stop `
                      @pkgMgmtPrefs
    }

    process
    {
        try
        {
            $startIn = '.'
            if( $Path )
            {
                if( (Test-Path -Path $Path -PathType Leaf) )
                {
                    $FileName = $Path | Split-Path -Leaf
                    $startIn = $Path | Split-Path -Parent
                }
                elseif( (Test-Path -Path $Path -PathType Container) )
                {
                    $startIn = $Path
                }
                else
                {
                    Write-Error -Message "Path ""$($Path)"" does not exist."
                    return
                }
            }

            $Force = $FileName.StartsWith('.')
            $prismJsonFiles = Get-ChildItem -Path $startIn -Filter $FileName -Recurse:$Recurse -Force:$Force -ErrorAction Ignore
            if( -not $prismJsonFiles )
            {
                $msg = ''
                $suffix = ''
                if( $Recurse )
                {
                    $suffix = 's'
                    $msg = ' or any of its sub-directories'
                }

                $locationMsg = 'the current directory'
                if( $startIn -ne '.' -and $startIn -ne (Get-Location).Path )
                {
                    $locationMsg = """$($startIn | Resolve-Path -Relative)"""
                }

                $msg = "No $($FileName) file$($suffix) found in $($locationMsg)$($msg)."
                Write-Error -Message $msg -ErrorAction Stop
                return
            }

            foreach( $prismJsonFile in $prismJsonFiles )
            {
                $prismJsonPath = $prismJsonFile.FullName
                $config = Get-Content -Path $prismJsonPath | ConvertFrom-Json
                if( -not $config )
                {
                    Write-Warning "File ""$($prismJsonPath | Resolve-Path -Relative) is empty."
                    continue
                }

                $lockBaseName = [IO.Path]::GetFileNameWithoutExtension($prismJsonPath)
                $lockExtension = [IO.Path]::GetExtension($prismJsonPath)
                # Hidden file with no extension, e.g. `.prism`
                if( -not $lockBaseName -and $lockExtension )
                {
                    $lockBaseName = $lockExtension
                    $lockExtension = ''
                }

                $ignore = @{ 'ErrorAction' = 'Ignore' }
                # public configuration that users can customize.
                # Add-Member doesn't return an object if the member already exists, so these can't be part of one pipeline.
                $config | Add-Member -Name 'PSModules' -MemberType NoteProperty -Value @() @ignore
                $config | Add-Member -Name 'PSModulesDirectoryName' -MemberType NoteProperty -Value 'PSModules' @ignore

                $privateModulePath =
                    Join-Path -Path $prismJsonFile.DirectoryName -ChildPath $config.PSModulesDirectoryName
                $lockPath =
                    Join-Path -Path ($prismJsonPath |
                    Split-Path -Parent) -ChildPath "$($lockBaseName).lock$($lockExtension)"
                $addMemberArgs = @{
                    MemberType = 'NoteProperty';
                    PassThru = $true;
                    # Force so users can't customize these properties.
                    Force = $true;
                }
                # Members that users aren't allowed to customize/override.
                $config |
                    Add-Member -Name 'Path' -Value $prismJsonPath @addMemberArgs |
                    Add-Member -Name 'File' -Value $prismJsonFile @addMemberArgs |
                    Add-Member -Name 'LockPath' -Value $lockPath @addMemberArgs |
                    Add-Member -Name 'PSModulesPath' -Value $privateModulePath @addMemberArgs |
                    Out-Null

                # This makes it so we can use PowerShell's module cmdlets as much as possible.
                $privateModulePath =  & {
                    # Prism's private module path, PSModules.
                    $config.PSModulesPath | Write-Output

                    # PackageManagement needs to be able to find and load PowerShellGet so it can get repositoriees,
                    # package sources, etc, so it and PowerShellGet have to be in PSModulePath, unfortunately.
                    Get-Module -Name 'PackageManagement','PowerShellGet' |
                        Select-Object -ExpandProperty 'Path' | # **\PSModules\MODULE\VERSION\MODULE.psd1
                        Split-Path -Parent |                   # **\PSModules\MODULE\VERSION
                        Split-Path -Parent |                   # **\PSModules\MODULE
                        Split-Path -Parent |                   # **\PSModules
                        Select-Object -Unique |
                        Write-Output
                }
                $env:PSModulePath = $privateModulePath -join [IO.Path]::PathSeparator
                Write-Debug -Message "env:PSModulePath  $($env:PSModulePath)"

                switch( $Command )
                {
                    'install' 
                    {
                        $config | Install-PrivateModule
                    }
                    'update'
                    {
                        $config | Update-ModuleLock
                    }
                }
            }
        }
        finally
        {
            $env:PSModulePath = $origModulePath
        }
    }
}

Set-Alias -Name 'prism' -Value 'Invoke-Prism'
