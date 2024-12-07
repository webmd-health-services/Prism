
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

        if (-not (Test-Path -Path $filePath))
        {
            New-Item -Path $filePath -ItemType File
        }

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
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position=0)]
            [hashtable] $Module,

            [String] $In,

            [String] $UsingDirName,

            [switch] $AsNestedModule,

            [switch] $InVersionedDirectory
        )

        if ($In)
        {
            $In = Join-Path -Path $script:testRoot -ChildPath $In
        }
        else
        {
            $In = $script:testRoot
        }

        if (-not $UsingDirName)
        {
            $UsingDirName = 'PSModules'

            if ($AsNestedModule)
            {
                $UsingDirName = 'Modules'
            }
        }

        $savePath = Join-Path -Path $In -ChildPath $UsingDirName
        $savePath = [IO.Path]::GetFullPath($savePath)

        # Make sure *only* the modules we requested are installed.
        $expectedCount = 0
        foreach ($moduleName in $Module.Keys)
        {
            $multipleVersions = ($Module[$moduleName] | Measure-Object).Count -gt 1

            $modulePath = Join-Path -Path $savePath -ChildPath $moduleName
            foreach ($semver in $Module[$moduleName])
            {
                $expectedCount += 1
                $version,$prerelease = $semver -split '-'
                $manifestPath = Join-Path -Path $modulePath -ChildPath "${moduleName}.psd1"
                if ($multipleVersions -or $InVersionedDirectory)
                {
                    $manifestPath | Should -Not -Exist -Because 'should use version directory'
                    $manifestPath = Join-Path -Path ($manifestPath | Split-Path -Parent) `
                                              -ChildPath "${version}\$($manifestPath | Split-Path -Leaf)"
                }

                $manifestPath | Should -Exist
                $manifest =
                    # Test-ModuleManifest caches and doesn't check if a manifest file ever gets updated later.
                    Start-Job { Test-ModuleManifest -Path $using:manifestPath } |
                    Receive-Job -AutoRemoveJob -Wait |
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

        Get-ChildItem -Path "${savePath}\*\*.psd1", "${savePath}\*\*.*.*\*.psd1" -ErrorAction Ignore |
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
            "PSModulesDirectoryName": "PSM1"
        }
'@
        GivenLockFile $script:latestNoOpLockFile
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' } -UsingDirName 'PSM1'
    }

    It 'does not install in a subdirectory' {
        GivenPrismFile @'
{
    "PSModulesDirectoryName": "."
}
'@
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
        ThenInstalled @{ 'NoOp' = '1.0.0' } -UsingDirName '.'
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

    It 'installs in versioned directory' {
        # Make sure when installing in a versioned directory, no other files or directories get deleted.
        GivenFile 'PSModules\NoOp\SomeFile.txt'
        GivenFile 'PSModules\NoOp\SomeDir\SomeFile.txt'
        # Make sure we know if/when PowerShell stops cleaning out destination directories.
        GivenFile 'PSModules\NoOp\1.0.0\SomeFile.txt'
        GivenPrismFile @'
{
    "FlattenModules": false
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
        WhenInstalling
        ThenInstalled @{ 'NoOp' = '1.0.0' } -InVersionedDirectory
        Join-Path -Path $script:testRoot -ChildPath 'PSModules\NoOp\SomeFile.txt' | Should -Exist
        Join-Path -Path $script:testRoot -ChildPath 'PSModules\NoOp\SomeDir\SomeFile.txt' | Should -Exist
        Join-Path -Path $script:testRoot -ChildPath 'PSModules\NoOp\1.0.0\SomeFile.txt' | Should -Not -Exist
    }

    Context 'installing nested module' {
        BeforeEach {
            # Make sure module.psd1 name matches the name of the parent directory because if a path in the PSModulePath
            # env var is the path to a module, Get-Module -List returns that module, not any nested modules.
            GivenFile "$($script:testRoot | Split-Path -Leaf).psd1"
        }

        It 'reduces nesting' {
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

        It 'reduces nesting for modules without a manifest' {
            Remove-Item -Path (Join-Path -Path $script:testRoot -ChildPath '*.psd1')
            GivenFile "$($script:testRoot | Split-Path -Leaf).psm1"
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

        It 'installs new version' {
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
            ThenSucceeded
            GivenLockFile @"
{
    "PSModules": [
        { "name": "NoOp", "version": "1.0.0", "repositorySourceLocation": "$($script:defaultLocation)" }
    ]
}
"@
            WhenInstalling
            ThenSucceeded
            ThenInstalled @{ 'NoOp' = '1.0.0' } -AsNestedModule
        }

        It 'validates old version removed' {
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
            ThenSucceeded

            GivenLockFile @"
{
    "PSModules": [
        { "name": "NoOp", "version": "1.0.0", "repositorySourceLocation": "$($script:defaultLocation)" }
    ]
}
"@
            Mock -CommandName 'Save-Module' -ModuleName 'Prism'
            Mock -CommandName 'Remove-Item' `
                 -ModuleName 'Prism' `
                 -ParameterFilter { ($Path | Split-Path -Leaf) -eq 'NoOp' }
            WhenInstalling -ErrorAction SilentlyContinue
            Should -Not -Invoke 'Save-Module' -ModuleName 'Prism'
            $Global:Error | Should -Match 'that destination already exists'
        }

        It 'customizes module directory name' {
            GivenPrismFile @'
{
    "PSModulesDirectoryName": "PSM1"
}
'@
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
            ThenInstalled @{ 'NoOp' = '1.0.0' } -AsNestedModule -UsingDirName 'PSM1'
        }

        It 'does not install in a subdirectory' {
            GivenPrismFile @'
{
    "PSModulesDirectoryName": "."
}
'@
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
            ThenInstalled @{ 'NoOp' = '1.0.0' } -AsNestedModule -UsingDirName '.'
        }
    }
}
