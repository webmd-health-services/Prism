<!--markdownlint-disable MD024 no-duplicate-heading-->

# Prism

## Overview

Prism is a PowerShell module manager inspired by NuGet. Run `prism install` in a source code repository and Prism will
save modules privately into a "PSModules" directory in that repository. Prism let's you:

* Package and deploy modules side-by-side with the app or tool that uses them without needing to install modules
  globally ahead of time.
* Not worry about what modules are or aren't installed. Scripts can import and use modules from the "PSModules"
  directory in the script's source code repository.
* Avoid comitting modules to the source code repository. Team members and build processes run `prism install` to
  get modules installed.

## System Requirements

* Windows PowerShell 5.1 and .NET 4.6.1+
* PowerShell 6+ on Windows, Linux, or macOS
* PackageManagement 1.3.2 to 1.4.8.1 and PowerShellGet 2.1.5 to 2.2.5.

## Installing

We recommend installing Prism globally from the PowerShell Gallery into the current user's scope:

```powershell
Install-Module -Name 'Prism' -Scope CurrentUser -Repository 'PSGallery' -Force
```

If you only have the "PSGallery" repository (run `Get-PSRepository` to get a list), you can omit the `-Repository`
parameter. If "PSGallery" repository is trusted (run `Set-PSRepository` to configure a repository's installation
policy), you cam omit the `-Force` parameter.

## Getting Started

In your source code repository, create a "prism.json" file in the root of your repository. It should have a `PSModules`
property that is an array of modules that should be installed.

```yaml
{
    "PSModules": [
        {
            "Name": "Whiskey",
            "Version": "0.*"
        },
        {
            "Name": "Yodel",
            "Version": "1.*"
        }
    ]
}
```

Then, open a PowerShell prompt in the same directory as the "prism.json" file and run

```powershell
prism install
```

When Prism is done running, there should be a PSModules directory in the current directory that contains all the
private modules listed in the prism.json file. There will also be a prism.lock.json file, which should also get
checked into source control along with the prism.json file.

## Adding to Builds

To add Prism to your build process, you'll need to install its dependencies, install Prism, then run it. Prism has an
init.ps1 script that can do all this for you. Each release of Prism has an init.ps1 script whose URL you can find on the
[GitHub releases page.](https://github.com/webmd-health-services/Prism/releases). Once you have the URL, you can add
this snippet to your build (replacing `VERSION` with the version of init.ps1 you want to use):

```powershell
Invoke-WebRequest 'https://github.com/webmd-health-services/Prism/releases/download/VERSION/init.ps1' | Invoke-Expression
prism install
```

If you always want to use the latest version of the init.ps1 script instead of pinning to a specific version,
[use this URL](https://raw.githubusercontent.com/webmd-health-services/Prism/main/init.ps1).

Make sure you've run `prism install` at least once, and check the file it creates, `prism.lock.json`, into your
repository. If you don't, the `prism install` command on the server will always generate the lock file, which makes
builds take longer.

## Configuration

### Overview

Each module object in the prism.json file must have a `Name` property, which is the name of the module to install. Each
object can also have a `Version` property, which is the version to install. Wildcards are supported, so you can pin to
the latest major, minor, or patch versions of a module. The default is to install the latest version of a module. To
allow pinning to prerelease versions, add an `AllowPrerelease` property whose value is `true`.

### Module Version

The `Version` property is optional. If omitted, Prism will install the latest version. Use wildcards to pin to specific
minor, patch, or prerelease versions of a module. Prism assumes modules use [Semantic Versioning](https://semver.org).

For example, if a module has versions `5.2.0-rc1`, `5.1.1`, `5.1.0`, `5.1.0-rc1`, `5.1.0-beta1`, `5.0.0`, `5.0.0-rc1`,
`4.10.1`, `4.10.0`, and `4.9.0`:

* `5.*` would pin the module to the latest release of version 5, `5.1.1` (prerelease versions are ignored).
* `4.10.*` would pin the module to the latest prerelease of version `4.10`, `4.10.1` (prerelease versions are ignored).
* `5.*-rc*` would pin the module to the latest release or prerelease of version 5, `5.2.0-rc1`. In order to use
prerelease versions, the version *must* contain a `-` prerelease prefix.

Modules are pinned/locked to a specific version of a module the first time `prism install` is run. The command generates
a `prism.lock.json` file, with the specific versions of each module to install. Once a lock file is created, `prism
install` will only install the module versions listed in the lock file. To update the versions in the lock file to
newer versions or to reflect changes made to the `prism.json` file, run `prism update`.

### Output Directory

Modules will always be saved in the same directory as the "prism.json" file, in a directory named "PSModules". You can
customize this directory name with the `PSModulesDirectoryName` option in your `prism.json` file:

```json
{
    "PSModules": [],
    "PSModulesDirectoryName": "Modules"
}
```

To put the PSModules directory in a *different* directory, put a "prism.json" file in that directory. Use the "prism"
command's `-Recurse` switch to run prism against every prism.json file under the current directory.

## Using Private Modules

### Importing

To use a private module installed by Prism, use `Import-Module` and pass the path to the module instead of a module
name. Use `Join-Path` and join the `$PSScriptRoot` automatic variable—the path to the current script's directory—with
the relative path to the module in the PSModules directory.

```powershell
# If a script is in the same directory as the "PSModules" directory.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSModules\Whiskey' -Resolve)

# If the script is in a sub-directory.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Whiskey' -Resolve)
```

## Using Nested Modules in a Module

### Installing

PowerShell has a 10 directory nested limit for nested modules. When using nested modules in a module, in order to avoid
errors about too much nesting, Prism will install the modules directly into your module directory and will also *not*
install modules into a version-specific directory. Prism automatically detects when installing into a module directory
by looking for a .psd1 or .psm1 file in the same directory as the prism.json file.

### Importing

To import and use a private, nested module installed by Prism, use `Import-Module` and pass the path to the module
instead of a module name. Use `Join-Path` and join the path to your module's directory with the relative path to the
module.

```powershell

$script:moduleDirPath = $PSScriptRoot

Import-Module -Name (Join-Path -Path $script:moduleDirPath -ChildPath 'Whiskey' -Resolve)
```

### Best Practices

#### In Scripts

***DO*** always use the `Import-Module` cmdlet's `Alias`, `Cmdlet`, and `Function` parameters to explicitly list what
commands your script is importing and using. It makes upgrading easier when you know what commands you're using.

***DO NOT*** depend on PowerShell's automatic module loading. That functionality won't see the private modules in
"PSModules".

#### When Writing Modules

***DO*** ship your module's dependencies as nested modules. Use Prism to manage these as it structures dependencies to
avoid deep nesting errors. Import dependencies from that private location. A module can have its own version of a module
loaded privately.

***DO NOT*** use the `NestedModules` module manifest property. Use an explicit `Import-Module` in your root module to
import dependencies saved inside your module.

***DO NOT*** use the `TypesToProcess` module manifest property, i.e. don't specify extended type data in a .ps1xml file.
PowerShell writes errors and refuses to import a module if its type file has previously been loaded. Instead, in your
root module, check if members are present on types, and add them using the `Update-TypeData` cmdlet if they are not
present.

***TRY NOT*** to use or load private assemblies (i.e. .dll files). Only one version of an assembly can be loaded at a
time, and once an assembly is loaded, PowerShell silently doesn't load other versions later. Users may get cryptic
errors about missing properties and objects. If you must use an assembly, add code in your root module to detect if the
correct version of your assembly is loaded, and write a terminating error if it isn't, asking the user to restart
PowerShell.

## Implementation

### PackageManagement and PowerShellGet

Prism requires that PackageManagement and PowerShellGet are installed and available globally. See the "System
Requiremens" for the versions of each that should be installed.

### prism install

For each module and version in the lock file, `prism install` calls the `Save-Module` cmdlet to install that specific
version. It passes the name of all installed repositories to the `Save-Module` cmdlet's `-Repository` parameter. The
`Save-Module` command loops through each repository, and installs the first module it finds.

The `prism install` command first uses `Get-Module` to see if the correct version of the module is installed in the
private PSModules directory. If it is, the module is not re-installed. If it isn't, the module is installed using the
`Save-Module` command.

### prism update

It calls `Find-Module` once to get the latest version of all the modules in the "prism.json" file. For each module with
a specific version that doesn't match the latest version, Prism will call `Find-Module` again to get all versions of
that module. (If the module's version from the "prism.json" file contains the prerelease suffix, `-`, or the build
suffix, `+`, or the `AllowPrerelease` proeprty exists and is set to `true`, prerelease versions will be included.) Prism
selects the first version returned by `Find-Module` that matches the version wildcard from the "prism.json" file. It
writes these versions to a lock file, which is used by the `prism install` command to install the modules.

## Troubleshooting

### Command Not Recognized

If you get an error that "The term 'prism' is not recognized as the name of a cmdlet, function, script file, or operable
program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.",
make sure Prism is actually installed. Run this command:

```powershell
Get-Module -Name Prism -ListAvailable
```

If the above command returns the module, it most likely means that your `$PSModuleAutoloadingPreference` variable is not
set to `ALL`. To fix this, you can:

* Set `$PSModuleAutoloadingPreference` to `ALL`.
* If `$PSModuleAutoloadingPreference` is set to `MODULEQUALIFIED`, run `Prism\prism install` instead.
* If `$PSModuleAutoloadingPreference` is set to `NONE`, import Prism first, `Import-Module Prism` then run
`prism install`.

## Bug Reports and Feature Requests

For bug reports and feature requests, [submit an issue](https://github.com/webmd-health-services/Prism/issues). If you
want to contribute a feature, enter an issue first and work with the team through the issue to discuss and get approval
before beginning.

## Changelog/Release Notes

See the [CHANGELOG](CHANGELOG.md). Also, the changelog and this readme are both included with the Prism module.
