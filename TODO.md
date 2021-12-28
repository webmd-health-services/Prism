# Using This Template

Click the "Use this template" button above. Clone the new repository. Run the `.\Initialize-Repository.ps1` script.
Pass the name of the module to the `ModuleName` parameter. The script will:

* Rename this file to TODO.md (there are additional steps to take afterward)
* Puts the default README.md file in place.
* Rename every file that has `PxGet` in its name, replacing `PxGet` with the module name.
* Replaces `PxGet` in every file with the module name.
* Installs and enables [Whiskey](https://github.com/webmd-health-services/Whiskey/wiki).
* Removes this script.
* If Git is installed, adds all the changes, and amends the initial commit with them so all traces of the template are
  removed.

# Manual Steps

Things you'll still need to do after creating your repository:

* Turn on branch protections.
* Create "develop" branch.
* Create a build in AppVeyor.
* Create a feature branch.
* Commit and push your new branch. A build should run in AppVeyor and finish successfully after a minute or so. The
default build will run using:
  * Windows PowerShell 5.1/.NET 4.6.2
  * Windows PowerShell 5.1/.NET 4.8
  * PowerShell 6.2 on Windows
  * PowerShell 7.1 on Windows
  * PowerShell 7.2 on Windows
  * PowerShell 7.1 on macOS
  * PowerShell 7.2 on Ubuntu