
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    $script:testRoot  = $null
    $script:moduleList = @()
    $script:failed = $false
    $script:testNum = 0

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

        if( $InstallPath )
        {
            Test-ModuleManifest -Path "$InstallPath\$ModuleName\$Version\$ModuleName.psd1" | Should -BeTrue
        }
        else 
        {
            Test-ModuleManifest -Path "$testRoot\PSModules\$ModuleName\$Version\$ModuleName.psd1" | Should -BeTrue
        }
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

Describe 'Invoke-Pxget' {
    BeforeEach { 
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory'
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

    It 'should pass when the module to be installed already exists' {
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
                    "Name": "NoOp",
                    "Version": "1.0.0"
                },
                {
                    "Name": "NoOp",
                    "Version": "1.0.1"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0'
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.1'
    }

    It 'should pass when given an install path' {
        New-Item -Path $(Join-Path -Path $testRoot -ChildPath 'TestPath') -ItemType 'Directory'
        $testPath = (Join-Path -Path $testRoot -ChildPath 'TestPath').replace('\', '\\')
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "NoOp",
                    "Version": "1.0.0",
                    "Path": "$($testPath)"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0' -InstallPath $testPath
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
        ThenInstalled -ModuleName 'NoOp' -Version '1.0.0'
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
}
