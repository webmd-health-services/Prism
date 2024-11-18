
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
    $script:result = $null
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

    function GivenFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [String] $WithContent,

            [String] $In = $script:testRoot
        )

        $filePath = Join-Path -Path $In -ChildPath $Named
        $dirPath = $filePath | Split-Path -Parent
        if (-not (Test-Path -Path $dirPath))
        {
            New-Item -Path $dirPath -ItemType Directory
        }

        New-Item -Path $filePath -ItemType File

        if ($WithContent)
        {
            $WithContent | Set-Content -Path $filePath -NoNewline
        }
    }

    function GivenPrismFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents,

            [String] $In = $script:testRoot
        )

        GivenFile 'prism.json' -In $In -WithContent $Contents
    }

    function GivenLockFile
    {
        param(
            [Parameter(Mandatory)]
            [String] $Contents,

            [String] $In = $script:testRoot
        )

        GivenFile 'prism.lock.json' -In $In -WithContent $Contents
    }

    function ThenInstalled
    {
        [CmdletBinding(DefaultParameterSetName='NonNested')]
        param(
            [Parameter(Mandatory, Position=0)]
            [hashtable] $Module,

            [String] $In,

            [Parameter(ParameterSetName='NonNested')]
            [String] $UsingDirName,

            [Parameter(Mandatory, ParameterSetName='Nested')]
            [switch] $AsNestedModule
        )

        if (-not $In)
        {
            $In = $script:testRoot
        }

        if (-not $UsingDirName)
        {
            $UsingDirName = 'PSModules'
        }

        $isNestedModule = $PSCmdlet.ParameterSetName -eq 'Nested'

        $savePath = $In
        if (-not $isNestedModule)
        {
            $savePath = Join-Path -Path $In -ChildPath $UsingDirName
        }

        # Make sure *only* the modules we requested are installed.
        $expectedCount = 0
        foreach ($moduleName in $Module.Keys)
        {
            $modulePath = Join-Path -Path $savePath -ChildPath $moduleName
            foreach ($semver in $Module[$moduleName])
            {
                $expectedCount += 1
                $version,$prerelease = $semver -split '-'
                $manifestPath = Join-Path -Path $modulePath -ChildPath $version
                if ($isNestedModule -and ($Module[$moduleName] | Measure-Object).Count -eq 1)
                {
                    $manifestPath | Should -Not -Exist -Because 'should remove version directory for nested module'
                    $manifestPath = $manifestPath | Split-Path -Parent
                }
                $manifestPath = Join-Path -Path $manifestPath -ChildPath "$($moduleName).psd1"
                $manifestPath | Should -Exist
                $manifest =
                    Test-ModuleManifest -Path $manifestPath |
                    Add-Member -Name 'SemVer' -MemberType ScriptProperty -Value {
                        $prerelease = $this.PrivateData['PSData']['PreRelease']
                        if ($prerelease)
                        {
                            $prerelease = "-$($prerelease)"
                        }
                        return "$($this.Version)$($prerelease)"
                    } -PassThru

                $manifest | Should -Not -BeNullOrEmpty
                $manifest.SemVer | Should -Be $semver
            }
        }

        $path = "${savePath}\*\*\*.psd1"
        if ($isNestedModule -and ($Module[$moduleName] | Measure-Object).Count -eq 1)
        {
            $path = "${savePath}\*\*.psd1"
        }

        Get-ChildItem -Path $path -ErrorAction Ignore |
            Select-Object -ExpandProperty 'DirectoryName' |
            Select-Object -Unique |
            Should -HaveCount $expectedCount
    }

    function ThenNotInstalled
    {
        param(
            [Parameter(Mandatory)]
            [String] $Module,

            [String] $In = $script:testRoot,

            [String] $UsingDirName = 'PSModules'
        )

        $savePath = $UsingDirName
        if ($In)
        {
            $savePath = Join-Path -Path $In -ChildPath $savePath
        }

        if (Test-Path -Path $savePath)
        {
            $installed = Get-ChildItem -Path $savePath
            $installed | Should -Not -Contain $Module
        }
        else
        {
            Test-Path -Path $savePath | Should -BeFalse
        }
    }

    function ThenReturned
    {
        param(
            [int] $ExpectedCount
        )

        $script:result | Should -HaveCount $ExpectedCount
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

        Push-Location $script:testRoot
        try
        {
            $script:result = Invoke-Prism -Command 'install' @WithParameters
        }
        finally
        {
            Pop-Location
        }
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
        $script:result = $null
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
        ThenReturned 1
    }

    # The only way this can happen is if someone manually updates their prism.lock.json file.
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
        ThenReturned 2
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
        ThenReturned 1
        Mock -CommandName 'Save-Module' -ModuleName 'Prism'
        WhenInstalling
        ThenReturned 0
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

    $skip = (Test-Path -Path 'variable:IsMacOS') -and $IsMacOS
    It 'should find repositories when Get-PSRepository has never been called before' -Skip:$skip {
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
        $prismJsonPath = Join-Path -Path $script:testRoot -ChildPath 'prism.json' -Resolve -ErrorAction Stop
        $importPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Prism' -Resolve
        Start-Job {
            $importPath = $using:importPath
            $prismJsonPath = $using:prismJsonPath

            Import-Module -Name $importPath
            prism install -Path $prismJsonPath
        } | Receive-Job -Wait -AutoRemoveJob
        ThenSucceeded
        ThenInstalled @{ 'NoOp' = '1.0.0' }
    }

    It 'should only install the specified modules' {
        GivenPrismFile @'
{
    "PSModules": [
        {
            "Name": "NoOp",
            "Version": "1.*"
        },
        {
            "Name": "Carbon",
            "Version": "2.*"
        },
        {
            "Name": "Whiskey",
            "Version": "0.*"
        }
    ]
}
'@
        GivenLockFile @"
{
    "PSModules":  [
        {
            "name":  "NoOp",
            "version":  "1.0.0",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        },
        {
            "name":  "Carbon",
            "version":  "2.11.1",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        },
        {
            "name":  "Whiskey",
            "version":  "0.61.0",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        }
    ]
}
"@
        WhenInstalling -WithParameters @{ Name = 'NoOp', 'Carbon' }
        ThenInstalled @{ 'NoOp' = '1.0.0' ; 'Carbon' = '2.11.1' }
        ThenNotInstalled 'Whiskey'
    }

    It 'should accept short hand syntax for array of names when installing modules' {
        GivenPrismFile @'
{
    "PSModules": [
        {
            "Name": "NoOp",
            "Version": "1.*"
        },
        {
            "Name": "Carbon",
            "Version": "2.*"
        },
        {
            "Name": "Whiskey",
            "Version": "0.*"
        }
    ]
}
'@
        GivenLockFile @"
{
    "PSModules":  [
        {
            "name":  "NoOp",
            "version":  "1.0.0",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        },
        {
            "name":  "Carbon",
            "version":  "2.11.1",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        },
        {
            "name":  "Whiskey",
            "version":  "0.61.0",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        }
    ]
}
"@
        Push-Location $script:testRoot
        # Testing shorthand syntax
        prism install 'NoOp', 'Carbon'
        Pop-Location
        ThenInstalled @{ 'NoOp' = '1.0.0' ; 'Carbon' = '2.11.1' }
        ThenNotInstalled 'Whiskey'
    }

    It 'should do nothing when module specified does not exist in the prism.lock.json file' {
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
        GivenLockFile @"
{
    "PSModules":  [
        {
            "name":  "NoOp",
            "version":  "1.0.0",
            "repositorySourceLocation":  "$($script:defaultLocation)"
        }
    ]
}
"@
        WhenInstalling -WithParameters @{ Name = 'Carbon'}
        ThenNotInstalled 'Carbon'
    }

    Context 'installing nested module' {
        It 'reduces nesting in module with <_> file' -ForEach @('module.psd1', 'module.psm1') {
            GivenFile $_
            GivenPrismFile '{}'
            GivenLockFile @'
{
    "PSModules": [
        {
            "name": "NoOp",
            "version": "1.0.0",
            "repositorySourceLocation": "https://www.powershellgallery.com/api/v2/"
        }
    ]
}
'@
            WhenInstalling
            ThenInstalled @{ 'NoOp' = '1.0.0' } -AsNestedModule
        }

        It 'does not reinstall if already installed' {
            GivenFile 'module.psd1'
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
            ThenInstalled @{ 'NoOp' = '1.0.0' } -AsNestedModule
            Mock -CommandName 'Save-Module' -ModuleName 'Prism'
            WhenInstalling
            Should -Invoke 'Save-Module' -ModuleName 'Prism' -Times 0 -Exactly
        }

        It 'installs multiple versions' {
            GivenFile 'module.psd1'
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
            ThenInstalled @{ 'Carbon' = @('2.11.1', '2.11.0') } -AsNestedModule
        }

        It 'installs prerelease modules' {
            GivenFile 'module.psd1'
            GivenPrismFile '{}'
            GivenLockFile @"
{
    "PSModules": [
        { "name": "NoOp", "version": "1.0.0-alpha26", "repositorySourceLocation": "$($script:defaultLocation)" }
    ]
}
"@
            WhenInstalling
            ThenInstalled @{ 'NoOp' = '1.0.0-alpha26' } -AsNestedModule
        }
    }
}
