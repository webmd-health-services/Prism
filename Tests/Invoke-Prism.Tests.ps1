
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

    function GivenPrismFile
    {
        param(
            [String] $Named = 'prism.json',

            [String] $WithContent = '{}'
        )

        $dir = Split-Path -Path $Named -Parent
        if( $dir )
        {
            New-Item -Path $dir -ItemType 'Directory' -Force
        }
        New-Item -Path $Named -ItemType 'File' -Value $WithContent
    }

    function ThenFailed
    {
        param(
            [Parameter(Mandatory)]
            [string] $WithErrorMatching
        )

        $failed | Should -BeTrue
        ThenWroteError -ThatMatches $WithErrorMatching
    }

    function ThenPackageManagementModulesImported
    {
        Get-Module -Name 'PackageManagement' |
            Where-Object 'Version' -ge ([Version]'1.3.2') |
            Where-Object 'Version' -le ([Version]'1.4.7') |
            Should -Not -BeNullOrEmpty -Because 'should import PackageManagement 1.3.2 - 1.4.7'

        Get-Module -Name 'PowerShellGet' |
            Where-Object 'Version' -ge ([Version]'2.0.0') |
            Where-Object 'Version' -le ([Version]'2.2.5') |
            Should -Not -BeNullOrEmpty -Because 'should import PowerShellGet 2.0.0 - 2.2.5'
    }

    function ThenRanCommand
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,
            
            [Parameter(Mandatory)]
            [hashtable[]] $Passing
        )
        $script:failed | Should -BeFalse
        $Global:Error | Should -BeNullOrEmpty

        $cmdName = (@{
            install = 'Install-PrivateModule';
            update = 'Update-ModuleLock';
        })[$Named]

        Assert-MockCalled -CommandName $cmdName -ModuleName 'Prism' -Times $Passing.Length -Exactly

        foreach( $config in $Passing )
        {
            if( -not $config['PSModulesDirectoryName'] )
            {
                $config['PSModulesDirectoryName'] = 'PSModules'
            }

            if( -not $config['PSModules'] )
            {
                $config['PSModules'] = @()
            }

            if( -not $config['LockPath'] )
            {
                $config['LockPath'] = 'prism.lock.json'
            }

            Write-Debug "$($config['Path'])"
            Assert-MockCalled -CommandName $cmdName -ModuleName 'Prism' -Times 1 -Exactly -ParameterFilter {
                $expectedPath = Join-Path -Path $script:testRoot -ChildPath $config['Path']
                Write-Debug "  Path      expected  $($expectedPath)"
                Write-Debug "            actual    $($Configuration.Path)"
                if( $Configuration.Path -ne $expectedPath )
                {
                    return $false
                }

                $expectedLockPath = Join-Path -Path $script:testRoot -ChildPath $config['LockPath']
                Write-Debug "  LockPath  expected  $($expectedLockPath)"
                Write-Debug "            actual    $($Configuration.LockPath)"
                if( $Configuration.LockPath -ne $expectedLockPath )
                {
                    return $false
                }
                Write-Debug "                      $($result)"

                $expectedDirName = $config['PSModulesDirectoryName']
                if( $Configuration.PSModulesDirectoryName -ne $expectedDirName )
                {
                    return $false
                }

                [Object[]]$expectedModules = $config['PSModules']
                if( $Configuration.PSModules.Length -ne $expectedModules.Length )
                {
                    return $false
                }

                for( $idx = 0; $idx -lt $expectedModules.Length; ++$idx )
                {
                    $expectedModule = $expectedModules[$idx]
                    $actualModule = $Configuration.PSModules[$idx]

                    if( $expectedModule.Name -ne $actualModule.Name )
                    {
                        return $false
                    }

                    if( $expectedModule.Version -ne $actualModule.Version )
                    {
                        return $false
                    }
                }

                return $true
            }
        }
    }

    function ThenWroteError
    {
        param(
            [Parameter(Mandatory)]
            [String] $ThatMatches
        )

        $Global:Error | Should -Not -BeNullOrEmpty
        $Global:Error | Should -Match $ThatMatches
    }

    function WhenInvokingCommand
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [hashtable] $WithParameters = @{},

            [Object] $WithPipelineInput
        )

        Mock -CommandName 'Install-PrivateModule' -ModuleName 'Prism'
        Mock -CommandName 'Update-ModuleLock' -ModuleName 'Prism'

        $WithParameters['Command'] = $Named
        try 
        {
            if( $WithPipelineInput )
            {
                $WithPipelineInput | Invoke-Prism @WithParameters
            }
            else
            {
                Invoke-Prism @WithParameters
            }
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

Describe 'Invoke-Prism' {
    BeforeEach { 
        $script:testRoot = $null
        $script:moduleList = @()
        $script:failed = $false
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        $script:psmodulePath = $env:PSModulePath
        New-Item -Path $script:testRoot -ItemType 'Directory'
        Push-Location $script:testRoot
        $Global:Error.Clear()
        Remove-Module -Name 'PowerShellGet', 'PackageManagement' -Force -ErrorAction Ignore
    }

    AfterEach {
        Pop-Location
        $Global:DebugPreference = $script:origDebugPref
        $Global:VerbosePreference = $script:origVerbosePref
        Remove-Item -Path 'env:PRISM_*' -ErrorAction Ignore
        # Make sure that the PSModulePath doesn't get changed.
        $env:PSModulePath | Should -Be $script:psmodulePath
    }

    Context 'command "<_>"' -Foreach @('install', 'update') {
        It 'should pass root configuration file' {
            $command = $_
            GivenPrismFile 'prism.json'
            GivenPrismFile 'dir1\prism.json'
            WhenInvokingCommand $command
            ThenRanCommand $command -Passing @{ 'Path' = 'prism.json'; 'LockPath' = 'prism.lock.json' }
            ThenPackageManagementModulesImported
        }

        It 'should pass all configuration files' {
            $command = $_
            GivenPrismFile 'prism.json'
            GivenPrismFile 'dir1\prism.json'
            GivenPrismFile 'dir1\dir2\prism.json'
            GivenPrismFile 'dir3\dir4\prism.json'
            WhenInvokingCommand $command -WithParameter @{ 'Recurse' = $true }
            ThenRanCommand $command -Passing @(
                @{ Path = 'prism.json' ; LockPath = 'prism.lock.json' },
                @{ Path = 'dir1\prism.json' ; LockPath = 'dir1\prism.lock.json' },
                @{ Path = 'dir1\dir2\prism.json' ; LockPath = 'dir1\dir2\prism.lock.json' },
                @{ Path = 'dir3\dir4\prism.json' ; LockPath = 'dir3\dir4\prism.lock.json' }
            )
            ThenPackageManagementModulesImported
        }
    }

    It 'should set configuration' {
        GivenPrismFile 'prism.json' -WithContent @'
{
    "PSModules": [
        {
            "Name": "NoOp"
        }
    ],
    "File": "should\\get\\overwritten",
    "LockPath": "should\\get\\overwritten",
    "Path": "should\\get\\overwritten",
    "PSModulesDirectoryName": "Modules"
}
'@
        WhenInvokingCommand 'install'
        ThenRanCommand 'install' -Passing @{
            Path = 'prism.json';
            LockPath = 'prism.lock.json';
            PSModulesDirectoryName = 'Modules';
            PSModules = @{ 'Name' = 'NoOp' }
        }
    }

    It 'should use custom configuration file name' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'module.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\module.json'
        GivenPrismFile 'dir1\dir2\prism.json'
        GivenPrismFile 'dir1\dir2\module.json'
        GivenPrismFile 'dir3\dir4\prism.json'
        GivenPrismFile 'dir3\dir4\module.json'
        WhenInvokingCommand 'install' -WithParameter @{ FileName = 'module.json' ; Recurse = $true }
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'module.json' ; LockPath = 'module.lock.json' },
            @{ Path = 'dir1\module.json' ; LockPath = 'dir1\module.lock.json' },
            @{ Path = 'dir1\dir2\module.json' ; LockPath = 'dir1\dir2\module.lock.json' },
            @{ Path = 'dir3\dir4\module.json' ; LockPath = 'dir3\dir4\module.lock.json' }
        )
    }

    It 'should support extensionless configuration file' {
        GivenPrismFile '.prism'
        WhenInvokingCommand 'install' -WithParameter @{ 'FileName' = '.prism' }
        ThenRanCommand 'install' -Passing @{ 'Path' = '.prism' ; LockPath = '.prism.lock'}
    }

    It 'should fail when no files found' {
        WhenInvokingCommand 'install' -ErrorAction SilentlyContinue
        ThenFailed "No prism\.json file found"
    }

    It 'should use prism.json file given by Path parameter' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\module.json'
        WhenInvokingCommand 'install' -WithParameter @{ 'Path' = 'dir1\module.json' }
        ThenRanCommand 'install' -Passing @{ Path = 'dir1\module.json' ; LockPath = 'dir1\module.lock.json' }
    }

    It 'should use prism.json file in directory given by Path parameter' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\dir2\prism.json'
        WhenInvokingCommand 'install' -WithParameter @{ 'Path' = 'dir1' }
        ThenRanCommand 'install' -Passing @{ Path = 'dir1\prism.json' ; LockPath = 'dir1\prism.lock.json' }
    }

    It 'should use all prism.json files found recursively under directory given by Path parameter' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\dir2\prism.json'
        WhenInvokingCommand 'install' -WithParameter @{ 'Path' = 'dir1' ; Recurse = $true ; }
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'dir1\prism.json' ; LockPath = 'dir1\prism.lock.json' },
            @{ Path = 'dir1\dir2\prism.json' ; LockPath = 'dir1\dir2\prism.lock.json' }
        )
    }

    It 'should fail if Path does not exist' {
        $parameters = @{ 'Path' = 'do_not_exist.json' }
        WhenInvokingCommand -Named 'install' -WithParameter $parameters -ErrorAction SilentlyContinue
        ThenWroteError '"do_not_exist.json" does not exist'
    }

    It 'should allow piping prism.json files' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\dir2\prism.json'
        WhenInvokingCommand 'install' -WithPipelineInput (Get-ChildItem -Path '.' -Filter 'prism.json' -Recurse)
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'prism.json' ; LockPath = 'prism.lock.json' },
            @{ Path = 'dir1\prism.json' ; LockPath = 'dir1\prism.lock.json' },
            @{ Path = 'dir1\dir2\prism.json' ; LockPath = 'dir1\dir2\prism.lock.json' }
        )
    }

    It 'should allow piping directories' {
        GivenPrismFile 'prism.json'
        GivenPrismFile 'dir1\prism.json'
        GivenPrismFile 'dir1\dir2\prism.json'
        WhenInvokingCommand 'install' -WithPipelineInput (Get-Item -Path 'dir1'),(Get-item -Path 'dir1\dir2')
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'dir1\prism.json' ; LockPath = 'dir1\prism.lock.json' },
            @{ Path = 'dir1\dir2\prism.json' ; LockPath = 'dir1\dir2\prism.lock.json' }
        )
    }

    It 'should allow custom-named prism.json file' {
        GivenPrismFile 'fubar.json'
        WhenInvokingCommand 'install' -WithParameter @{ FileName = 'fubar.json' }
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'fubar.json' ; LockPath = 'fubar.lock.json' }
        )
    }

    It 'should ignore prism.json when using custom named prism.json file' {
        GivenPrismFile 'prism.json'
        WhenInvokingCommand 'install' -WithParameter @{ FileName = 'fubar.json' } -ErrorAction SilentlyContinue
        ThenFailed -WithErrorMatching 'No fubar\.json file found'
    }
}
