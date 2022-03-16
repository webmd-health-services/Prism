# 0.3.0

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


# 0.1.3

* Improvements to documentation.


# 0.1.2

* Fixed: no progress shown to the user about what `prism install` is doing.
* Fixed: The `prism install` command fails to import its private PackageManagement and PowerShellGet modules in a
fresh repository.
* Fixed: The `prism install` command makes duplicate calls to `Find-Module`, which is slow.
* Fixed: Progress output from the `Save-Module` command shows when running the `prism install` command.


# 0.1.1

## Fixed

* Module fails to publish to PowerShell Gallery. 