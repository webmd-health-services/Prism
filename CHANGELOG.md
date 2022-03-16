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