
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

$rootDirectory = $null
$moduleList = @()
$failed = $false

BeforeAll {
    function Init
    {
        $script:rootDirectory = Get-RootDirectory
        $script:moduleList = @()
        $script:failed = $false
        $Global:Error.Clear()
    }

    function AddModule
    {
        param(
            [Parameter(Mandatory)]
            [string] $Name,
    
            [Parameter(Mandatory)]
            [string] $Version
        )
    
        $module = @{
            Name = $Name;
            Version = $Version;
        }
    
        $script:moduleList += $module
    }
    
    function CreatePxGetFile
    {
        $data = @"
        {
            "PSModules": [
    
"@
    
        foreach ($module in $moduleList) 
        {
            $data = $data + @"
                {
                    "Name": "$($module.Name)",
                    "Version": "$($module.Version)"
                }
"@
            if( $module -ne $moduleList[-1] )
            {
                $data = $data + ','
            }
        }
    
        $data = $data + @"
    
            ]
        }
"@
    
        New-Item -Path $rootDirectory -ItemType 'File' -Name "pxget.json" -Value $data
    }
    
    function Get-RootDirectory
    {
        return (Get-Item $(Get-Location)).Parent.FullName
    }
    
    function RemovePxGetFile
    {
        Remove-Item -Path "$rootDirectory\pxget.json"
    }
    
    function Reset
    {
        RemovePxGetFile
    }

    function ThenFailed
    {
        param(
            [Parameter(Mandatory)]
            $WithError
        )
    
        $script:failed | Should -BeTrue
        $Global:Error[-1] | Should -Match $WithError
    }    

    function ThenModuleNotFound
    {
        param(
            [Parameter(Mandatory)]
            $WithError
        )
    
        $Global:Error[-1] | Should -Match $WithError
    }
    
    function ThenSucceeded
    {
        $script:failed | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty
    }
    
    function WhenInvokingPxGet
    {
        # param(
        #     [switch] $WithNoPxGetFile
        # )

        # if( $WithNoPxGetFile )
        # {
        #     Mock -CommandName 'Get-Content' -ModuleName 'PxGet'
        # }

        try 
        {
            Invoke-PxGet 'install'
        }
        catch 
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_ -ErrorAction $ErrorActionPreference
        }
    }
}

Describe 'Invoke-PxGet.when there is a valid module in the pxget file' {
    AfterEach{ Reset }
    It 'should pass' {
        Init
        AddModule -Name 'PackageManagement' -Version '1.4.7'
        CreatePxGetFile
        WhenInvokingPxGet
        ThenSucceeded
    }
}

Describe 'Invoke-PxGet.when the module to be installed already exists' {
    AfterEach{ Reset }
    It 'should pass' {
        Init
        AddModule -Name 'PackageManagement' -Version '1.4.7'
        CreatePxGetFile
        WhenInvokingPxGet
        ThenSucceeded
    }
}

Describe 'Invoke-PxGet.when the module to be installed has a prerelease version' {
    AfterEach{ Reset }
    It 'should pass' {
        Init
        AddModule -Name 'PackageManagement' -Version '1.2.0-preview'
        CreatePxGetFile
        WhenInvokingPxGet
        ThenSucceeded
    }
}

Describe 'Invoke-PxGet.when there are multiple modules listed in the pxget file' {
    AfterEach{ Reset }
    It 'should pass' {
        Init
        AddModule -Name 'PackageManagement' -Version '1.4.7'
        AddModule -Name 'PowerShellGet' -Version '2.2.5'
        CreatePxGetFile
        WhenInvokingPxGet
        ThenSucceeded
    }
}

Describe 'Invoke-PxGet.when no modules are found matching the modules listed in the pxget file' {
    AfterEach{ Reset }
    It 'should run but throw an exception' {
        Init
        AddModule -Name 'Invalid' -Version '9.9.9'
        CreatePxGetFile
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenModuleNotFound -WithError 'No match was found for the specified search criteria and module name'
    }
}

Describe 'Invoke-PxGet.when there is no pxget file' {
    It 'should fail' {
        Init
        WhenInvokingPxGet -WithNoPxGetFile -ErrorAction SilentlyContinue
        ThenFailed -WithError 'does not exist'
    }
}

Describe 'Invoke-PxGet.when there are no modules listed in pxget file' {
    AfterEach{ Reset }
    It 'should fail' {
        Init
        CreatePxGetFile
        WhenInvokingPxGet -ErrorAction SilentlyContinue
        ThenFailed -WithError 'The argument is null'
    }
}
