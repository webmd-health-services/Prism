
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    $script:testRoot  = $null
    $script:testNum = 0
    $script:latestNoOpModule = Find-Module -Name 'NoOp' | Select-Object -First 1
    $script:psgalleryLocation = Get-PSRepository -Name 'PSGallery' | Select-Object -ExpandProperty 'SourceLocation'

    function GivenPrismFile
    {
        param(
            [Parameter(Mandatory, Position=0)]
            [string] $Contents,

            [String] $At = 'prism.json'
        )

        $directory = $At | Split-Path -Parent
        if( $directory )
        {
            New-Item -Path $directory -ItemType 'Directory' -Force | Out-Null
        }

        New-Item -Path $testRoot  -ItemType 'File' -Name $At -Value $Contents
    }

    function ThenLockFileIs
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position=0)]
            [Object] $ExpectedConfiguration,

            [String] $In = $script:testRoot
        )

        $path = Join-Path -Path $In -ChildPath 'prism.lock.json'
        $path | Should -Exist
        # ConvertTo-Json behaves differently across platforms and versions.
        Get-Content -Raw -Path $path | Should -Be ($ExpectedConfiguration | ConvertTo-Json)
    }

    function WhenLocking
    {
        [CmdletBinding()]
        param(
            [switch] $Recursively
        )

        $optionalParams = @{}
        if( $Recursively )
        {
            $optionalParams['Recurse'] = $true
        }
        $result = Invoke-Prism -Command 'update' @optionalParams
        $result | Out-String | Write-Verbose -Verbose
    }
}

Describe 'prism update' {
    BeforeEach { 
        $script:testRoot = $null
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory'
        $Global:Error.Clear()
        Push-Location $script:testRoot
    }

    AfterEach {
        Pop-Location
    }

    It 'should resolve exact versions' {
        GivenPrismFile @'
{
    "PSModules": [
        { "Name": "Carbon", "Version": "2.11.1" },
        { "Name": "NoOp", "Version": "1.0.0" }
    ]
}
'@
        WhenLocking
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'Carbon';
                    version = '2.11.1';
                    location = $script:psgalleryLocation;
                },
                [pscustomobject]@{
                    name ='NoOp';
                    version = '1.0.0';
                    location = $script:psgalleryLocation;
                }
            );
        })
    }

    It 'should resolve latest version by default' {
        GivenPrismFile @'
    {
        "PSModules": [ { "Name": "NoOp" }]
    }
'@
        WhenLocking
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'NoOp';
                    version = $script:latestNoOpModule.Version;
                    location = $script:psgalleryLocation;
                 }
            )
        })
    }

    It 'should resolve wildcards' {
        GivenPrismFile @'
{
    "PSModules": [
        { "Name": "NoOp", "Version": "1.*" }
    ]
}
'@
        WhenLocking
        $expectedModule =
            Find-Module -Name 'NoOp' -AllVersions | Where-Object 'Version' -like '1.*' | Select-Object -First 1
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'NoOp';
                    version = $expectedModule.Version;
                    location = $script:psgalleryLocation;
                }
            )
        })
    }

    It 'should automatically allow prerelease versions' {
        GivenPrismFile @'
{
    "PSModules": [
        { "Name": "Carbon", "Version": "2.*-*" }
    ]
}
'@
        WhenLocking
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'Carbon';
                    version = '2.11.1-alpha732';
                    location = $script:psgalleryLocation;
                }
            )
        })
    }

    It 'should allow user to enable prerelease versions' {
        GivenPrismFile @'
{
    "PSModules": [
        { "Name": "Carbon", "Version": "*alpha732", "AllowPrerelease": true }
    ]
}
'@
        WhenLocking
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'Carbon';
                    version = '2.11.1-alpha732';
                    location = $script:psgalleryLocation;
                }
            )
        })
    }

    It 'should lock recursively' {
        GivenPrismFile -At 'dir1\prism.json' @'
{
    "PSModules": [
        { "Name": "NoOp" }
    ]
}
'@
        GivenPrismFile -At 'dir1\dir2\prism.json' @'
{
    "PSModules": [
        { "Name": "NoOp" }
    ]
}
'@
        WhenLocking -Recursively
        $expectedLock = [pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'NoOp';
                    version = $script:latestNoOpModule.Version;
                    location = $script:psgalleryLocation;
                 }
            )
        } 
        ThenLockFileIs $expectedLock -In 'dir1'
        ThenLockFileIs $expectedLock -In 'dir1\dir2'
    }

    It 'should clobber existing lock file' {
        GivenPrismFile @'
    {
        "PSModules": [ { "Name": "NoOp" }]
    }
'@
        'clobberme' | Set-Content -Path 'prism.lock.json'
        WhenLocking
        Get-Content -Path 'prism.lock.json' -Raw | Should -Not -Match 'clobberme'
        ThenLockFileIs ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{
                    name = 'NoOp';
                    version = $script:latestNoOpModule.Version;
                    location = $script:psgalleryLocation;
                 }
            )
        })
    }
}