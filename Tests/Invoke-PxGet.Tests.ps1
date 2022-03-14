
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
            [String] $Named = 'pxget.json',

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
        $Global:Error[-1] | Should -Match $WithErrorMatching
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

        Assert-MockCalled -CommandName $cmdName -ModuleName 'PxGet' -Times $Passing.Length -Exactly

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
                $config['LockPath'] = 'pxget.lock.json'
            }

            Write-Debug "$($config['Path'])"
            Assert-MockCalled -CommandName $cmdName -ModuleName 'PxGet' -Times 1 -Exactly -ParameterFilter {
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
    
    function WhenInvokingCommand
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [hashtable] $WithParameters = @{}
        )

        Mock -CommandName 'Install-PrivateModule' -ModuleName 'PxGet'
        Mock -CommandName 'Update-ModuleLock' -ModuleName 'PxGet'

        try 
        {
            Invoke-PxGet -Command $Named @WithParameters
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
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        $script:psmodulePath = $env:PSModulePath
        New-Item -Path $script:testRoot -ItemType 'Directory'
        Push-Location $script:testRoot
        $Global:Error.Clear()
    }

    AfterEach {
        Pop-Location
        $Global:DebugPreference = $script:origDebugPref
        $Global:VerbosePreference = $script:origVerbosePref
        Remove-Item -Path 'env:PXGET_*' -ErrorAction Ignore
        # Make sure that the PSModulePath doesn't get changed.
        $env:PSModulePath | Should -Be $script:psmodulePath
    }

    Context 'command "<_>"' -Foreach @('install', 'update') {
        It 'should pass root configuration file' {
            $command = $_
            GivenPxGetFile 'pxget.json'
            GivenPxGetFile 'dir1\pxget.json'
            WhenInvokingCommand $command
            ThenRanCommand $command -Passing @{ 'Path' = 'pxget.json'; 'LockPath' = 'pxget.lock.json' }
        }

        It 'should pass all configuration files' {
            $command = $_
            GivenPxGetFile 'pxget.json'
            GivenPxGetFile 'dir1\pxget.json'
            GivenPxGetFile 'dir1\dir2\pxget.json'
            GivenPxGetFile 'dir3\dir4\pxget.json'
            WhenInvokingCommand $command -WithParameter @{ 'Recurse' = $true }
            ThenRanCommand $command -Passing @(
                @{ Path = 'pxget.json' ; LockPath = 'pxget.lock.json' },
                @{ Path = 'dir1\pxget.json' ; LockPath = 'dir1\pxget.lock.json' },
                @{ Path = 'dir1\dir2\pxget.json' ; LockPath = 'dir1\dir2\pxget.lock.json' },
                @{ Path = 'dir3\dir4\pxget.json' ; LockPath = 'dir3\dir4\pxget.lock.json' }
            )
        }
    }

    It 'should set configuration' {
        GivenPxGetFile 'pxget.json' -WithContent @'
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
            Path = 'pxget.json';
            LockPath = 'pxget.lock.json';
            PSModulesDirectoryName = 'Modules';
            PSModules = @{ 'Name' = 'NoOp' }
        }
    }

    It 'should use custom configuration file name' {
        GivenPxGetFile 'pxget.json'
        GivenPxGetFile 'module.json'
        GivenPxGetFile 'dir1\pxget.json'
        GivenPxGetFile 'dir1\module.json'
        GivenPxGetFile 'dir1\dir2\pxget.json'
        GivenPxGetFile 'dir1\dir2\module.json'
        GivenPxGetFile 'dir3\dir4\pxget.json'
        GivenPxGetFile 'dir3\dir4\module.json'
        WhenInvokingCommand 'install' -WithParameter @{ FileName = 'module.json' ; Recurse = $true }
        ThenRanCommand 'install' -Passing @(
            @{ Path = 'module.json' ; LockPath = 'module.lock.json' },
            @{ Path = 'dir1\module.json' ; LockPath = 'dir1\module.lock.json' },
            @{ Path = 'dir1\dir2\module.json' ; LockPath = 'dir1\dir2\module.lock.json' },
            @{ Path = 'dir3\dir4\module.json' ; LockPath = 'dir3\dir4\module.lock.json' }
        )
    }

    It 'should support extensionless configuration file' {
        GivenPxGetFile '.pxget'
        WhenInvokingCommand 'install' -WithParameter @{ 'FileName' = '.pxget' }
        ThenRanCommand 'install' -Passing @{ 'Path' = '.pxget' ; LockPath = '.pxget.lock'}
    }

    It 'should fail when no files found' {
        WhenInvokingCommand 'install' -ErrorAction SilentlyContinue
        ThenFailed "No pxget\.json file found"
    }

}
