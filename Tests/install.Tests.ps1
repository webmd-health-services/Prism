
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    $script:testRoot  = $null
    $script:moduleList = @()
    $script:failed = $false
    $script:testNum = 0
    $script:origProgressPref = $Global:ProgressPreference
    $script:origVerbosePref = $Global:VerbosePreference
    $script:origDebugPref = $Global:DebugPreference
    $Global:ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    $script:psgalleryLocation = Get-PSRepository -Name 'PSGallery' | Select-Object -ExpandProperty 'SourceLocation'
    $script:latestNoOpLockFile = @"
{
    "PSModules": { "name": "NoOp", "version": "1.0.0", "location": "$($script:psgallerylocation)" }
}
"@

    function GivenPxGetFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents
        )

        $Contents | Set-Content -Path 'pxget.json' -NoNewline
    }

    function GivenLockFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents
        )

        $Contents | Set-Content -Path 'pxget.lock.json' -NoNewline
    }

    function ThenInstalled
    {
        param(
            [Parameter(Mandatory)]
            [hashtable] $Module,

            [String] $In = 'PSModules'
        )

        # Make sure *only* the modules we requested are installed.
        $expectedCount = 0
        foreach( $moduleName in $Module.Keys )
        {
            $modulePath = Join-Path -Path $In -ChildPath $moduleName
            foreach( $semver in $Module[$moduleName] )
            {
                $expectedCount += 1
                $version,$prerelease = $semver -split '-'
                $manifestPath = Join-Path -Path $modulePath -ChildPath $version
                $manifestPath = Join-Path -Path $manifestPath -ChildPath "$($moduleName).psd1"
                $manifestPath | Should -Exist
                $manifest =
                    Test-ModuleManifest -Path $manifestPath |
                    Add-Member -Name 'SemVer' -MemberType ScriptProperty -Value {
                        $prerelease = $this.PrivateData['PSData']['PreRelease']
                        if( $prerelease )
                        {
                            $prerelease = "-$($prerelease)"
                        }
                        return "$($this.Version)$($prerelease)"
                    } -PassThru

                $manifest | Should -Not -BeNullOrEmpty
                $manifest.SemVer | Should -Be $semver
            }
        }
        Get-ChildItem -Path "$($In)\*\*\*.psd1" -ErrorAction Ignore |
            Select-Object -ExpandProperty 'DirectoryName' |
            Select-Object -Unique |
            Should -HaveCount $expectedCount
    }
    
    function ThenSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
    }
    
    function WhenInstalling
    {
        [CmdletBinding()]
        param(
        )

        Invoke-PxGet -Command 'install' |
            Format-Table |
            Out-String |
            Write-Verbose -Verbose
    }
}

AfterAll {
    $Global:ProgressPreference = $script:origProgressPref
}

Describe 'pxget install' {
    BeforeEach { 
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory'
        Push-Location $script:testRoot
    }

    AfterEach {
        $Global:DebugPreference = $script:origDebugPref
        $Global:VerbosePreference = $script:origVerbosePref
        Remove-Item -Path 'env:PXGET_*' -ErrorAction Ignore
        Pop-Location
    }

    It 'should create lock and install module' {
        GivenPxGetFile @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0"
                }
            ]
        }
"@
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' }
        'pxget.lock.json' | Should -Exist
        $expectedContent = ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{ name = 'NoOp'; version = '1.0.0'; location = $script:psgalleryLocation }
            )}) | ConvertTo-Json
        Get-Content -Path 'pxget.lock.json' -Raw | Should -Be $expectedContent
    }

    It 'should install multiple versions' {
        GivenPxGetFile '{}' # install only cares about pxget.lock.json
        GivenLockFile @"
{
    "PSModules": [
        { "name": "Carbon", "version": "2.11.1", "location": "$($script:psgallerylocation)" },
        { "name": "Carbon", "version": "2.11.0", "location": "$($script:psgallerylocation)" }
    ]
}
"@
        WhenInstalling
        ThenInstalled @{ 'Carbon' = @('2.11.1', '2.11.0') }
    }

    It 'should install PackageManagement and PowerShellGet' {
        GivenPxGetFile '{}'
        # Has to be the same version as used by PxGet internally.
        $pkgMgmtVersion = 
            Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\PxGet\Modules\PackageManagement') |
            Select-Object -ExpandProperty 'Name'
        $psGetVersion = 
            Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\PxGet\Modules\PowerShellGet') |
            Select-Object -ExpandProperty 'Name'
        GivenLockFile @"
{
    "PSModules": [
        { "name": "PackageManagement", "version": "$($pkgMgmtVersion)", "location": "$($script:psgalleryLocation)" },
        { "name": "PowerShellGet", "version": "$($psGetVersion)", "location": "$($script:psgalleryLocation)" }
    ]
}
"@
        WhenInstalling
        ThenInstalled @{ 'PackageManagement' = $pkgMgmtVersion ; 'PowerShellGet' = $psGetVersion ; }
    }

    It 'should pass and install to custom PSModules directory' {
        GivenPxGetFile @'
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0"
                }
            ],
            "PSModulesDirectoryName": "Modules"
        }
'@
        GivenLockFile $script:latestNoOpLockFile
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' } -In 'Modules'
    }

    It 'should install prerelease versions' {
        GivenPxGetFile '{}'
        GivenLockFile ('{ "PSModules": { "name": "NoOp", "version": "1.0.0-alpha26", ' +
                      """location"": ""$($script:psgallerylocation)"" } }")
        WhenInstalling
        ThenInstalled @{ 'NoOp' = @('1.0.0-alpha26') }
    }

    It 'should install multiple modules' {
        GivenPxGetFile '{}'
        GivenLockFile ("{ ""PSModules"": [ " +
            "{ ""name"": ""NoOp"", ""version"": ""1.0.0"", ""location"": ""$($script:psgallerylocation)"" }, " +
            "{ ""name"": ""Carbon"", ""version"": ""2.11.0"", ""location"": ""$($script:psgallerylocation)"" }" +
        "] }")
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' ; 'Carbon' = '2.11.0' ; }
    }

    It 'should handle empty lock file' {
        GivenPxGetFile '{}'
        GivenLockFile '{}'
        WhenInstalling
        ThenSucceeded
        ThenInstalled @{}
    }

    It 'should turn off verbose output in package management modules' {
        GivenPxGetFile '{}'
        GivenLockFile $script:latestNoOpLockFile
        $env:PXGET_DISABLE_DEEP_VERBOSE = 'True'
        $Global:VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInstalling 4>&1
        $output | Write-Verbose -Verbose
        # From Import-Module.
        $output |
            Where-Object { $_ -like 'Loading module from path ''*PackageManagement.psd1''.' } |
            Should -BeNullOrEmpty
        $output |
            Where-Object { $_ -like 'Loading module from path ''*PowerShellGet.psd1''.' } |
            Should -BeNullOrEmpty
        # From PackageManagement.
        $output |
            Where-Object { $_ -like 'Using the provider ''PowerShellGet'' for searching packages.' } |
            Should -BeNullOrEmpty
        # From PowerShellGet.
        $output |
            Where-Object { $_ -like 'Module ''NoOp'' was saved successfully to path ''*''.' } |
            Should -BeNullOrEmpty
    }


    It 'should turn off debug output in package management modules' {
        GivenPxGetFile '{}'
        GivenLockFile $script:latestNoOpLockFile
        $env:PXGET_DISABLE_DEEP_DEBUG = 'True'
        $Global:DebugPreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInstalling 5>&1
        $output | Write-Verbose -Verbose
        # Import-Module doesn't output any debug messages.
        # Save-Module does.
        # From PowerShellGet. Can't find PackageManagement-only debug messages.
        $output |
            Where-Object { $_ -like '*PackagePRovider::FindPackage with name NoOp' } |
            Should -BeNullOrEmpty
    }
}
