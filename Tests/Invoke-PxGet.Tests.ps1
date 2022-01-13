
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    $script:testRoot  = $null
    $script:moduleList = @()
    $script:failed = $false
    $script:testNum = 0
    
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    function Init
    {
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()

        # Remove when done testing.
        $DebugPreference = 'Continue'
        Write-Debug "Get-Location: $(Get-Location)"
    }
    
    function GivenPxGetFile
    {
        param(
            [Parameter(Mandatory)]
            [string] $Contents
        )

        New-Item -Path $testRoot  -ItemType 'File' -Name "pxget.json" -Value $Contents
    }

    function New-TestRoot
    {
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testRoot -ItemType 'Directory'
        # Remove when done testing.
        $DebugPreference = 'Continue'
        Write-Debug "Test Root: $testRoot"
    }

    function RemovePxGetFile
    {
        if( Test-Path -Path "$testRoot \pxget.json" )
        {
            Remove-Item -Path "$testRoot \pxget.json"
        }
    }
    
    function Reset
    {
        RemovePxGetFile
    }

    function ThenFailed
    {
        param(
            [Parameter(Mandatory)]
            [string] $WithError
        )
    
        $script:failed | Should -BeTrue
        $Global:Error[-1] | Should -Match $WithError
    }    

    function ThenModuleNotFound
    {
        param(
            [Parameter(Mandatory)]
            [string] $WithError
        )
    
        $Global:Error[-1] | Should -Match $WithError
    }
    
    function ThenSucceeded
    {
        $script:failed | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
        Assert-MockCalled -CommandName 'Get-RootDirectory' -ModuleName 'PxGet' -Times 2
    }
    
    function WhenInvokingPxGet
    {
        try 
        {
            Mock -CommandName 'Get-RootDirectory' -ModuleName 'PxGet' { return $testRoot}
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
        Init
        New-TestRoot 
    }
    AfterEach { 
        Reset 
    }

    It 'should pass when there is a valid module in the pxget file' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "PackageManagement",
                    "Version": "1.4.7"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should pass when the module to be installed already exists' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "PackageManagement",
                    "Version": "1.4.7"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should pass when the module to be installed is a prerelease version' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "PackageManagement",
                    "Version": "1.2.0-preview"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should pass when there are multiple modules to be installed' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "PackageManagement",
                    "Version": "1.4.7"
                },
                {
                    "Name": "PowerShellGet",
                    "Version": "2.2.5"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet
        ThenSucceeded
    }

    It 'should run but throw an exception when there is an invalid module name' {
        $contents = @"
        {
            "PSModules": [
                {
                    "Name": "Invalid",
                    "Version": "9.9.9"
                }
            ]
        }
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenModuleNotFound -WithError "Cannot bind argument to parameter 'Modules' because it is null."
    }

    It 'should pass when the pxget exists but is empty file is empty' {
        $contents = @"
    
"@
        GivenPxGetFile -Contents $contents
        WhenInvokingPxGet -ErrorAction SilentlyContinue
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
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenSucceeded
    }

    It 'should fail when there is no pxget file' {
        WhenInvokingPxGet -WithNoPxGetFile -ErrorAction SilentlyContinue
        ThenFailed -WithError 'does not exist'
    }
}
