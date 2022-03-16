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

        # The name of the Prism configuration file to use. Defaults to `prism.json`.
        [String] $FileName = 'prism.json',

        [switch] $Recurse
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $origModulePath = $env:PSModulePath

    $pkgMgmtPrefs = Get-PackageManagementPreference
    try
    {
        # prism should ship with its own private copies of PackageManagement and PowerShellGet. Setting PSModulePath
        # to prism module's Modules directory ensures no other package modules get loaded.
        $pkgManagementModulePath = Join-Path -Path $moduleRoot -ChildPath 'PSModules'
        $env:PSModulePath = $pkgManagementModulePath
        Write-Debug 'AVAILABLE MODULES'
        Get-Module -ListAvailable | Format-Table -AutoSize | Out-String | Write-Debug
        Import-Module -Name 'PackageManagement' @pkgMgmtPrefs
        Import-Module -Name 'PowerShellGet' @pkgMgmtPrefs
        Write-Debug 'IMPORTED MODULES'
        Get-Module | Format-Table -AutoSize | Out-String | Write-Debug

        Write-Debug 'AVAILABLE MODULES'
        Write-Debug "PSModulePath  $($env:PSModulePath)"
        Get-Module -ListAvailable | Format-Table -AutoSize | Out-String | Write-Debug

        $Force = $FileName.StartsWith('.')
        $prismJsonFiles = Get-ChildItem -Path '.' -Filter $FileName -Recurse:$Recurse -Force:$Force -ErrorAction Ignore
        if( -not $prismJsonFiles )
        {
            $msg = ''
            $suffix = ''
            if( $Recurse )
            {
                $suffix = 's'
                $msg = ' or any of its sub-directories'
            }

            $msg = "No $($FileName) file$($suffix) found in the current directory$($msg)."
            Write-Error -Message $msg -ErrorAction Stop
            return
        }

        foreach( $prismJsonFile in $prismJsonFiles )
        {
            $path = $prismJsonFile.FullName
            $config = Get-Content -Path $path | ConvertFrom-Json
            if( -not $config )
            {
                Write-Warning "File ""$($path | Resolve-Path -Relative) is empty."
                continue
            }

            $lockBaseName = [IO.Path]::GetFileNameWithoutExtension($path)
            $lockExtension = [IO.Path]::GetExtension($path)
            # Hidden file with no extension, e.g. `.prism`
            if( -not $lockBaseName -and $lockExtension )
            {
                $lockBaseName = $lockExtension
                $lockExtension = ''
            }

            $lockPath = Join-Path -Path ($path | Split-Path -Parent) -ChildPath "$($lockBaseName).lock$($lockExtension)"
            # private members that users aren't allowed to customize.
            $config |
                Add-Member -Name 'Path' -MemberType NoteProperty -Value $path -PassThru -Force |
                Add-Member -Name 'File' -MemberType NoteProperty -Value $prismJsonFile -PassThru -Force |
                Add-Member -Name 'LockPath' -MemberType NoteProperty -Value $lockPath -PassThru -Force |
                Out-Null

            $ignore = @{ 'ErrorAction' = 'Ignore' }
            # public configuration that users can customize.
            # Add-Member doesn't return an object if the member already exists, so these can't be part of the pipeline.
            $config | Add-Member -Name 'PSModules' -MemberType NoteProperty -Value @() @ignore
            $config | Add-Member -Name 'PSModulesDirectoryName' -MemberType NoteProperty -Value 'PSModules' @ignore

            # This makes it so we can use PowerShell's module cmdlets as much as possible.
            $privateModulePath =  Join-Path -Path $prismJsonFile.DirectoryName -ChildPath $config.PSModulesDirectoryName
            $env:PSModulePath = "$($privateModulePath)$([IO.Path]::PathSeparator)$($pkgManagementModulePath)"

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

Set-Alias -Name 'prism' -Value 'Invoke-Prism'
