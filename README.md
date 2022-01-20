# Overview

The PxGet module is a tool similar to nuget but for PowerShell modules. A pxget.json file is located in the root of a
repository that specifies what modules should be installed into the PSModules directory of the repository. PxGet should
ship with its own private copies of PackageManagement and PowerShellGet.

# System Requirements

* Windows PowerShell 5.1 and .NET 4.6.1+
* PowerShell Core 6+ on Windows, Linux, or macOS

# Installing

To install globally:

```powershell
Install-Module -Name 'PxGet'
Import-Module -Name 'PxGet'
```

To install privately:

```powershell
Save-Module -Name 'PxGet' -Path '.'
Import-Module -Name '.\PxGet'
```
