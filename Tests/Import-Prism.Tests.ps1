
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    function GivenModuleLoaded
    {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Prism\Prism.psd1' -Resolve)
        Get-Module -Name 'Prism' | Add-Member -MemberType NoteProperty -Name 'NotReloaded' -Value $true
    }

    function GivenModuleNotLoaded
    {
        Remove-Module -Name 'Prism' -Force -ErrorAction Ignore
    }
    function ThenModuleLoaded
    {
        $module = Get-Module -Name 'Prism'
        $module | Should -Not -BeNullOrEmpty
        $module | Get-Member -Name 'NotReloaded' | Should -BeNullOrEmpty
    }

    function WhenImporting
    {
        $script:importedAt = Get-Date
        Start-Sleep -Milliseconds 1
        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Prism\Import-Prism.ps1' -Resolve)
    }
}

Describe 'Import-Prism' {
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
