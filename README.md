# Overview

PxGet is a PowerShell module manager inspired by NuGet. Run `pxget install` in a source code repository and PxGet will
save modules privately into a "PSModules" directory in that repository. PxGet let's you:

* Package and deploy modules side-by-side with the app or tool that uses them without needing to install
modules globally ahead of time.
* Not worry about what modules are or aren't installed. Scripts can import and use modules from the "PSModules"
directory in the script's source code repository.
* Avoid comitting modules to the source code repository. Team members and build processes run `pxget install` to
get modules installed.


# System Requirements

* Windows PowerShell 5.1 and .NET 4.6.1+
* PowerShell 6+ on Windows, Linux, or macOS


# Installing

We recommend installing PxGet globally from the PowerShell Gallery into the current user's scope:

```powershell
Install-Module -Name 'PxGet' -Scope CurrentUser -Repository 'PSGallery' -Force
```

If you only have the "PSGallery" repository (run `Get-PSRepository` to get a list), you can omit the `-Repository`
parameter. If "PSGallery" repository is trusted (run `Set-PSRepository` to configure a repository's installation
policy), you cam omit the `-Force` parameter.


# Getting Started

In your source code repository, create a "pxget.json" file in the root of your repository. It should have a `PSModules`
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

Then, open a PowerShell prompt in the same directory as the "pxget.json" file and run

```powershell
pxget install
```

When PxGet is done running, there should be a "PSModules" directory in the current directory that contains all the
private modules listed in the "pxget.json" file. There will also be a "pxget.lock.json" file, which should also get
checked into source control with the "pxget.json" file.


# Adding to Builds

To add PxGet to your build process, you'll need to install then run it. Run these PowerShell commands together or
separately:

```powershell
Find-Module -Name 'PxGet' | Select-Object -First 1 | Install-Module -Scope CurrentUser -Force
pxget install | Format-Table
```

Use the `-Force` switch with `Install-Module` so the module gets installed even if the repository it is being installed
from is untrusted.

The `Select-Object -First 1` command is included in case your build server has multiple PowerShell repositories defined.
You can omit it if there is only one, or use the `Find-Module` command's `Repository` parameter to import from a
specific repository.

The `pxget install` command returns module objects (returned by `Get-Module`). Some build systems display those as a
list instead of a table, so we pipe the install output to `Format-Table` to make it look better in build output.

Make sure you've run `pxget install` at least once, and check the file it creates, `pxget.lock.json`, into your
repository. If you don't, the `pxget install` command on the server will always generate the lock file, which will make
builds take longer.


# Configuration

## Overview

Each module object in the "pxget.json" file can have `Name` and `Version` properties. Only `Name` is mandatory,
and it must be the name of the module to install. The same module may be listed multiple times, if you need multiple
versions.

## Module Version

The `Version` property is optional. If omitted, PxGet will always install the latest version. Use wildcards to pin to
specific minor, patch, or prerelease versions of a module. PxGet assumes modules use
[Semantic Versioning](https://semver.org).

For example, if a module has versions `5.2.0-rc1`, `5.1.1`, `5.1.0`, `5.1.0-rc1`, `5.1.0-beta1`, `5.0.0`, `5.0.0-rc1`,
`4.10.1`, `4.10.0`, and `4.9.0`:

* `5.*` would pin the module to the latest release of version 5, `5.1.1` (prerelease versions are ignored).
* `4.10.*` would pin the module to the latest prerelease of version `4.10`, `4.10.1` (prerelease versions are ignored).
* `5.*-rc*` would pin the module to the latest release or prerelease of version 5, `5.2.0-rc1`. In order to use
prerelease versions, the version *must* contain a `-` prerelease prefix.

Modules are pinned/locked to a specific version of a module the first time `pxget install` is run. The command generates
a `pxget.lock.json` file, with the specific versions of each module to install. Once a lock file is created, `pxget
install` will only install the module versions listed in the lock file. To update the versions in the lock file to
newer versions or to reflect changes made to the `pxget.json` file, run `pxget update`.

## Output Directory

Modules will always be saved in the same directory as the "pxget.json" file, in a directory named "PSModules". You can
customize this directory name with the `PSModulesDirectoryName` option in your `pxget.json` file:

```json
{
    "PSModules": [],
    "PSModulesDirectoryName": "Modules"
}
```

To put the PSModules directory in a *different* directory, put a "pxget.json" file in that directory. Use the "pxget"
command's `-Recurse` switch to run pxget against every pxget.json file under the current directory.


# Using Private Modules

## Importing

To use a private module installed by PxGet, use `Import-Module` and pass the path to the module instead of a module
name. Use `Join-Path` and join the `$PSScriptRoot` automatic variable—the path to the current script's directory—with
the relative path to the module in the PSModules directory.

```powershell
# If a script is in the same directory as the "PSModules" directory.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSModules\Whiskey' -Resolve)

# If the script is in a sub-directory.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Whiskey' -Resolve)
```

## Best Practices

### In Scripts

***DO*** always use the `Import-Module` cmdlet's `Alias`, `Cmdlet`, and `Function` parameters to explicitly list what
commands your script is importing and using. It makes upgrading easier when you know what commands you're using.

***DO NOT*** depend on PowerShell's automatic module loading. That functionality won't see the private modules in
"PSModules".

### When Writing Modules

***DO*** ship your module's dependencies as nested modules, preferably in a "Modules" directory. Import dependencies
from that private location. A module can have its own version of a module loaded privately.

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


# Implementation

## Overview

PxGet uses its own private copies of the `PackageManagement` and `PowerShellGet` modules to find and install modules.

## pxget install

For each module and version in the lock file, `pxget install` calls the `Save-Module` cmdlet to install that specific
version. It passes the name of all installed repositories to the `Save-Module` cmdlet's `-Repository` parameter. The
`Save-Module` command loops through each repository, and installs the first module it finds.

The `pxget install` command first uses `Get-Module` to see if the correct version of the module is installed in the
private PSModules directory. If it is, the module is not re-installed. If it isn't, the module is installed using the
`Save-Module` command.

## pxget update

It calls`Find-Module` once to get the latest version of all the modules in the "pxget.json" file. For each module with a
specific version that doesn't match the latest version, PxGet will call `Find-Module` again to get all versions of that
module. (If the module's version from the "pxget.json" file contains the prerelease suffix, `-`, prerelease versions
will be included.) PxGet selects the first version returned by `Find-Module` that matches the version wildcard from the
"pxget.json" file. It writes these versions to a lock file, which is used by the `pxget install` command to install
the modules.


# Troubleshooting

## Command Not Recognized

If you get an error that "The term 'pxget' is not recognized as the name of a cmdlet, function, script file, or operable
program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.",
make sure PxGet is actually installed. Run this command:

```powershell
Get-Module -Name PxGet -ListAvailable
```

If the above command returns the module, it most likely means that your `$PSModuleAutoloadingPreference` variable is not
set to `ALL`. To fix this, you can:

* Set `$PSModuleAutoloadingPreference` to `ALL`.
* If `$PSModuleAutoloadingPreference` is set to `MODULEQUALIFIED`, run `PxGet\pxget install` instead.
* If `$PSModuleAutoloadingPreference` is set to `NONE`, import PxGet first, `Import-Module PxGet` then run
`pxget install`.


# FAQ

## Why didn't you use PSDepends?

We tried to reach out to the author of PSDepends to see if they would take feature enhancements and bug requests, but
we never heard back.

## Why isn't this called "PSGet"/"psget"?

The "PS" prefix is reserved by the PowerShell team. We thought the "x" in "PxGet" was a cool replacement. Our hope is
that the team working on the PowerShellGet module sees our work and creates a similar "psget" command in PowerShellGet.


# Bug Reports and Feature Requests

For bug reports and feature requests, [submit an issue](https://github.com/webmd-health-services/PxGet/issues). If you
want to contribute a feature, enter an issue first and work with the team through the issue to discuss and get approval
before beginning.


# Changelog/Release Notes

See the [CHANGELOG](CHANGELOG.md). Also, the changelog and this readme are both included with the PxGet module.

