
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

    function GivenPxGetFile
    {
        param(
            [Parameter(Mandatory)]
            [string] $Contents
        )

        New-Item -Path $testRoot  -ItemType 'File' -Name "pxget.json" -Value $Contents
    }

    function ThenError
    {
        param(
            [Parameter(Mandatory)]
            [string] $Matches
        )
    
        $Global:Error[-1] | Should -Match $Matches
    }

    function ThenInstalled
    {
        param(
            [Parameter(Mandatory)]
            [string] $ModuleName,

            [Parameter(Mandatory)]
            [string] $Version,

            [string] $InstallPath
        )

        $prerelease = ''
        if( $Version -match '^(.*)-(.*)$' )
        {
            $Version = $Matches[1]
            $prerelease = $Matches[2]
        }

        if( -not $InstallPath )
        {
            $InstallPath = Join-Path -Path $testRoot -ChildPath 'PSModules'
        }

        $manifestPath = Join-Path -Path $InstallPath -ChildPath $ModuleName
        $manifestPath = Join-Path -Path $manifestPath -ChildPath $Version
        $manifestPath = Join-Path -Path $manifestPath -ChildPath "$ModuleName.psd1"
        $manifestPath | Should -Exist
        $manifest = Test-ModuleManifest -Path $manifestPath
        # For PowerShell 5.1
        if( -not ($manifest | Get-Member -Name 'Prerelease') )
        {
            $manifest | Add-Member -Name 'Prerelease' -MemberType ScriptProperty -Value { $this.PrivateData['PSData']['Prerelease'] }
        }

        $manifest | Should -Not -BeNullOREmpty
        $manifest.Name | Should -Be $ModuleName
        $manifest.Version | Should -Be $Version
        $manifest.Prerelease | Should -Be $prerelease
    }
    
    function ThenSucceeded
    {
        $script:failed | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
        Assert-MockCalled -CommandName 'Get-Location' -ModuleName 'PxGet' -Times 2
    }
    
    function WhenInvokingPxGet
    {
        [CmdletBinding()]
        param(
        )

        try 
        {
            Mock -CommandName 'Get-Location' -ModuleName 'PxGet' { return $testRoot }
            Invoke-PxGet 'install'
        }
        catch 
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_ -ErrorAction $ErrorActionPreference
        }
    }
}

AfterAll {
    $Global:ProgressPreference = $script:origProgressPref
}

Describe 'Invoke-Pxget' {
    BeforeEach { 
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory'
    }

    AfterEach {
        $Global:DebugPreference = $script:origDebugPref
        $Global:VerbosePreference = $script:origVerbosePref
        Remove-Item -Path 'env:PXGET_*' -ErrorAction Ignore
    }

    It 'should pass when there is a valid module in the pxget file' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0'
    }

    It 'should pass when different versions of the same module are installed' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "Carbon",
                    "Version": "2.11.0"
                },
                {
                    "Name": "Carbon",
                    "Version": "2.10.0"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'Carbon' -Version '2.11.0'
        ThenInstalled -ModuleName 'Carbon' -Version '2.10.0'
    }

    It 'should pass when given an install path that exists' {
        $testPath = Join-Path -Path $testRoot -ChildPath 'TestPath'
        New-Item -Path $testPath -ItemType 'Directory'
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0",
                    "Path": $($testPath | ConvertTo-Json)
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0' -InstallPath $testPath
    }

    It 'should pass when given an install path that does not exist' {
        $testPath = Join-Path -Path $testRoot -ChildPath 'NewPath'
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0",
                    "Path": $($testPath | ConvertTo-Json)
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0' -InstallPath $testPath
    }

    It 'should pass and install to PSModules directory if path is null or empty' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0",
                    "Path": ""
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0'
    }

    It 'should pass when the module to be installed is a prerelease version' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0-alpha26"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0-alpha26'
    }

    It 'should pass when there are multiple modules to be installed' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0"
                },
                {
                    "Name": "Carbon",
                    "Version": "2.11.0"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0'
        ThenInstalled -ModuleName 'Carbon' -Version '2.11.0'
    }

    It 'should run but write an error when there is an invalid module name' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "Invalid",
                    "Version": "9.9.9"
                },
                {
                    "Name": "Invalid2",
                    "Version": "9.9.9"
                },
                {
                    "Name": "ProgetAutomation",
                    "Version": "1.0.0"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenError -Matches ([regex]::Escape('Module(s) "Invalid", "Invalid2" not found.'))
        ThenInstalled -ModuleName 'ProGetAutomation' -Version '1.0.0'
    }

    It 'should pass when the pxget file is empty' {
        $contents = @"
    
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should pass when there are no modules listed in the pxget file' {
        $contents = @"
        {
            "PSModules": [
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should fail when there is no pxget file' {
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenError -Matches 'There is no pxget.json file in the current directory.'
    }

    It 'should turn off verbose output in package management modules' {
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
        $env:PXGET_DISABLE_DEEP_VERBOSE = 'True'
        $Global:VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInvokingPxGet 4>&1
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
        $env:PXGET_DISABLE_DEEP_DEBUG = 'True'
        $Global:DebugPreference = [Management.Automation.ActionPreference]::Continue
        $output = WhenInvokingPxGet 5>&1

        # Import-Module doesn't output any debug messages.
        # Save-Module does.
        # From PowerShellGet. Can't find PackageManagement-only debug messages.
        $output |
            Where-Object { $_ -like '*PackagePRovider::FindPackage with name NoOp' } |
            Should -BeNullOrEmpty
    }
}
