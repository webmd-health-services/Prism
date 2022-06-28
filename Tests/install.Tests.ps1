
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
    $script:latestNoOpModule = Find-Module -Name 'NoOp' | Select-Object -First 1
    $script:defaultLocation =
        Get-PSRepository -Name $script:latestNoOpModule.Repository | Select-Object -ExpandProperty 'SourceLocation'
    $script:latestNoOpLockFile = @"
{
    "PSModules": { 
        "name": "NoOp",
        "version": "$($script:latestNoOpModule.Version)",
        "repositorySourceLocation": "$($script:defaultLocation)"
    }
}
"@

    function GivenPrismFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents,
            
            [String] $In
        )

        $path = 'prism.json'
        if( $In )
        {
            New-Item -Path $In -ItemType 'Directory' -Force | Out-Null
            $path = Join-Path -Path $In -ChildPath $path
        }

        $Contents | Set-Content -Path $path -NoNewline
    }

    function GivenLockFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents,
            
            [String] $In
        )

        $path = 'prism.lock.json'
        if( $In )
        {
            New-Item -Path $In -ItemType 'Directory' -Force | Out-Null
            $path = Join-Path -Path $In -ChildPath $path
        }

        $Contents | Set-Content -Path $path -NoNewline
    }

    function ThenInstalled
    {
        param(
            [Parameter(Mandatory)]
            [hashtable] $Module,

            [String] $In,
            
            [String] $UsingDirName = 'PSModules'
        )

        $savePath = $UsingDirName
        if( $In )
        {
            $savePath = Join-Path -Path $In -ChildPath $savePath
        }

        # Make sure *only* the modules we requested are installed.
        $expectedCount = 0
        foreach( $moduleName in $Module.Keys )
        {
            $modulePath = Join-Path -Path $savePath -ChildPath $moduleName
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

        Get-ChildItem -Path "$($savePath)\*\*\*.psd1" -ErrorAction Ignore |
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
            [hashtable] $WithParameters = @{}
        )

        Invoke-Prism -Command 'install' @WithParameters |
            Out-String |
            Write-Verbose
    }
}

AfterAll {
    $Global:ProgressPreference = $script:origProgressPref
}

Describe 'prism install' {
    BeforeEach { 
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory' -ErrorAction Ignore
        Push-Location $script:testRoot
    }

    AfterEach {
        $Global:DebugPreference = $script:origDebugPref
        $Global:VerbosePreference = $script:origVerbosePref
        Remove-Item -Path 'env:PRISM_*' -ErrorAction Ignore
        Pop-Location
    }

    It 'should create lock and install module' {
        GivenPrismFile @"
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
        'prism.lock.json' | Should -Exist
        $expectedContent = ([pscustomobject]@{
            PSModules = @(
                [pscustomobject]@{ name = 'NoOp'; version = '1.0.0'; repositorySourceLocation = $script:defaultLocation }
            )}) | ConvertTo-Json
        Get-Content -Path 'prism.lock.json' -Raw | Should -Be $expectedContent
    }

    It 'should install multiple versions' {
        GivenPrismFile '{}' # install only cares about prism.lock.json
        GivenLockFile @"
{
    "PSModules": [
        { "name": "Carbon", "version": "2.11.1", "repositorySourceLocation": "$($script:defaultLocation)" },
        { "name": "Carbon", "version": "2.11.0", "repositorySourceLocation": "$($script:defaultLocation)" }
    ]
}
"@
        WhenInstalling
        ThenInstalled @{ 'Carbon' = @('2.11.1', '2.11.0') }
    }

    It 'should pass and install to custom PSModules directory' {
        GivenPrismFile @'
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
        ThenInstalled @{ 'NoOp' = '1.0.0' } -UsingDirName 'Modules'
    }

    It 'should install prerelease versions' {
        GivenPrismFile '{}'
        GivenLockFile ('{ "PSModules": { "name": "NoOp", "version": "1.0.0-alpha26", ' +
                      """repositorySourceLocation"": ""$($script:defaultLocation)"" } }")
        WhenInstalling
        ThenInstalled @{ 'NoOp' = @('1.0.0-alpha26') }
    }

    It 'should install multiple modules' {
        GivenPrismFile '{}'
        GivenLockFile ("{ ""PSModules"": [ " +
            "{ ""name"": ""NoOp"", ""version"": ""1.0.0"", ""repositorySourceLocation"": ""$($script:defaultLocation)"" }, " +
            "{ ""name"": ""Carbon"", ""version"": ""2.11.0"", ""repositorySourceLocation"": ""$($script:defaultLocation)"" }" +
        "] }")
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' ; 'Carbon' = '2.11.0' ; }
    }

    It 'should handle empty lock file' {
        GivenPrismFile '{}'
        GivenLockFile '{}'
        WhenInstalling
        ThenSucceeded
        ThenInstalled @{}
    }

    It 'should turn off verbose output in package management modules' {
        GivenPrismFile '{}'
        GivenLockFile $script:latestNoOpLockFile
        $env:PRISM_DISABLE_DEEP_VERBOSE = 'True'
        $Global:VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInstalling 4>&1
        $output | Write-Verbose
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
        GivenPrismFile '{}'
        GivenLockFile $script:latestNoOpLockFile
        $env:PRISM_DISABLE_DEEP_DEBUG = 'True'
        $Global:DebugPreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInstalling 5>&1
        $output | Write-Verbose
        
        # Import-Module doesn't output any debug messages.
        # Save-Module does.
        # From PowerShellGet. Can't find PackageManagement-only debug messages.
        $output |
            Where-Object { $_ -like '*PackagePRovider::FindPackage with name NoOp' } |
            Should -BeNullOrEmpty
    }

    It 'should install in same directory as prism JSON file' {
        GivenPrismFile '{}' -In 'dir1\dir2'
        GivenLockFile $script:latestNoOpLockFile -In 'dir1\dir2'
        WhenInstalling -WithParameters @{ Recurse = $true }
        ThenInstalled @{ 'NoOp' = '1.0.0' } -In 'dir1\dir2'
    }

    It 'should not reinstall if already installed' {
        GivenPrismFile @"
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
        Mock -CommandName 'Save-Module' -ModuleName 'Prism'
        WhenInstalling
        Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Prism' -Times 0 -Exactly
    }

    It 'should handle missing forward slash on PSGallery location on older platforms' {
        GivenPrismFile @'
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.*"
                }
            ]
        }
'@
        GivenLockFile @'
{
    "PSModules":  [
        {
            "name":  "NoOp",
            "version":  "1.0.0",
            "repositorySourceLocation":  "https://www.powershellgallery.com/api/v2"
        }
    ]
}
'@
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' }
    }


    It 'should handle extra forward slash on PSGallery location' {
        GivenPrismFile @'
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.*"
                }
            ]
        }
'@
        GivenLockFile @'
{
    "PSModules":  [
        {
            "name":  "NoOp",
            "version":  "1.0.0",
            "repositorySourceLocation":  "https://www.powershellgallery.com/api/v2/"
        }
    ]
}
'@
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' }
    }
}
