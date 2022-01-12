
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    function GivenModuleLoaded
    {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PxGet\PxGet.psd1' -Resolve)
        Get-Module -Name 'PxGet' | Add-Member -MemberType NoteProperty -Name 'NotReloaded' -Value $true
    }

    function GivenModuleNotLoaded
    {
        Remove-Module -Name 'PxGet' -Force -ErrorAction Ignore
    }

    function Init
    {

    }

    function ThenModuleLoaded
    {
        $module = Get-Module -Name 'PxGet'
        $module | Should -Not -BeNullOrEmpty
        $module | Get-Member -Name 'NotReloaded' | Should -BeNullOrEmpty
    }

    function WhenImporting
    {
        $script:importedAt = Get-Date
        Start-Sleep -Milliseconds 1
        & (Join-Path -Path $PSScriptRoot -ChildPath '..\PxGet\Import-PxGet.ps1' -Resolve)
    }
}

Describe 'Import-PxGet' {
    BeforeEach { Init }

    It 'should import the module when it is not loaded' {
        GivenModuleNotLoaded
        WhenImporting
        ThenModuleLoaded
    }

    It 'should re-import the module if the module is already loaded' {
        GivenModuleLoaded
        WhenImporting
        ThenModuleLoaded
    }
}
