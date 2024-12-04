<!--markdownlint-disable MD012 no-multiple-blanks-->
<!--markdownlint-disable MD024 no-duplicate-heading-->

# Prism Changelog

## 0.9.1

Fixed: if the latest non-prerelease version of a module matches the wildcard in the "prism.json" file and the latest
version is a prerelease version and the `AllowPrerelease` flag is `true` in the "prism.json" file, Prism fails to pin
to the prerelease version.

## 0.9.0

> Released 3 Dec 2024

Turns out, the 10 directory nesting limit for nested modules is a scope stack limit, not a directory limit. This version
of Prism now installs nested modules into a "Modules" directory instead of directly in the module directory. You can
preserve the old behavior and install modules directly in the module directory by setting the "PSModulesDirectoryName"
configuration property in the prism.json file to `.`.

## 0.8.1

> Released 19 Nov 2024

Fixed: Prism fails to install new versions of nested modules if old versions are installed.

## 0.8.0

> Released 18 Nov 2024

### Nesting Improvements

PowerShell has a 10 directory nesting limit for nested modules.In order to prvent this nesting limit, Prism now:

* installs nested modules directly in the module directory instead of a "PSModules" directory.
* moves modules out of the versioned directory where PowerShell installs them by default (unless a module depends on
  multiple versions of the same module).

Prism determines if it is installing nested modules by looking for a .psd1 or .psm1 file in the same directory as the
prism.json file.

### Changes

* The "PSModulesDirectoryName" configuration option can no longer be a path.
* The `prism install` command now only returns objects for modules that were actually installed.
* The `prism update` command now only returns objects for modules whose version changed/updated.
* Prism now saves modules to the lock file in alphabetical order.
* The `prism update` command now shows the previous version number a module was pinned to.
* The `prism update` command no longer changes the repository location a module is locked to. Previously, if a module
  was found in multiple repositories, the lock file could sometimes change the repository location.

## 0.7.0

> Released 27 Aug 2024

Added the ability to install or update a subset of the modules listed in the prism.json file. Specify the subset of
modules by passing it to the `Name` parameter when invoking prism.


## 0.6.1

> Released 29 Jan 2024

Fixed: Prism fails to find modules that only have prerelease versions.


## 0.6.0

> Released 8 Aug 2022

* Adding an init.ps1 script that can be used to install Prism's dependencies (PackageManagement and PowerShellGet
modules) and install Prism.


## 0.5.2

> Released 4 Aug 2022

* Adding support for PackageManagement 1.4.8.1.


## 0.5.1

> Released 13 Jul 2022

## Fixed

* `prism install` fails if `Get-PSRepository` hasn't been run before it.
* Prism commands are very slow in Windows PowerShell on Windows 10, Server 2012R2, and Server 2019 due to some overzealous logging.


## 0.5.0

> Released 6 Jul 2022

## Changed

* Prism supports PackageManagement versions 1.3.2 through 1.4.7.
* Prism supports PowerShellGet versions 2.0.0 through 2.2.5.

## Fixed

* Fixed: Prism commands fail if PowerShellGet and PackageManagement modules aren't already imported before being run.


## 0.4.0

> Released 28 Jun 2022

## Added

* Added "Path" parameter to all prism commands, which can be the path to a specific prism.json file, or a directory
  containing a prism.json file.
* Added ability to pipe prism.json files and/or directories containing prism.json files to prism.

## Changed

* Prism now requires PackageManagement and PowerShellGet to be pre-installed.

## Fixed

* Fixed: `prism install` always installs modules, even if they are already installed.
* Fixed: module install fails if lock file generated on Windows 10/Server 2016 or later and install is on Windows
  8.1/Server 2012 R2 and vice-versa. (PSGallery repository's URL ends with a forward slash on
  Windows 8.1/Server 2012 R2, but ends with no forward slash on later operating systems.)


## 0.3.0

> Released 17 Mar 2022

## Upgrade Instructions

* Regenerate any lock files created with the previous version of Prism. We changed the name of one of the properties.
* If you use the `Location` property on any object returned by the `install` or `update` commands, rename the property
  to `RepositorySourceLocation`.

## Added

* Added default formats for the objects returned by the `install` and `update` commands so they are formatted in a table
by default.

## Changed

* Renamed the `location` property in lock files to `repositorySourceLocation`.
* Renamed the `Location` property on objects returned by the `install` and `update` commands to
`RepositorySourceLocation`.

## Fixed

* Modules from prism.json files in sub-directories are installed in the current directory instead of the directory of
  the prism.json file.


## 0.2.0

> Released 16 Mar 2022

## Upgrade Instructions

We've renamed PxGet to Prism.

* Rename your `pxget.json` files to `prism.json` files.
* Update scripts that call `pxget` to call `prism` instead.
* Update scripts that install `PxGet` module to install `Prism` instead.
* Make sure all computers that will use the same prism.json file have PowerShell repositories defined with the same
  "SourceLocation" property. The `install` command now installs from a lock file, which records what specific version of
  a module to install and the repository from which to install it.

## Added

* An `update` command that takes the versions in the prism.json file and locks/pins them to a specific version, saving
  the version and repository source location to a new prism.lock.json file.

## Changed

* Renamed PxGet to Prism.
* The `install` command determines what to install using a prism.lock.json file, which is generated by the new `update`
  command. If a lock file doesn't exist, the `install` command will call the `update` command first.


## 0.1.3

* Improvements to documentation.


## 0.1.2

* Fixed: no progress shown to the user about what `prism install` is doing.
* Fixed: The `prism install` command fails to import its private PackageManagement and PowerShellGet modules in a
fresh repository.
* Fixed: The `prism install` command makes duplicate calls to `Find-Module`, which is slow.
* Fixed: Progress output from the `Save-Module` command shows when running the `prism install` command.


## 0.1.1

## Fixed

* Module fails to publish to PowerShell Gallery.
