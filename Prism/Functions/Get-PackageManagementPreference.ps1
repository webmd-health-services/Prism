
function Get-PackageManagementPreference
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $deepPrefs = @{}
    if( (Test-Path -Path 'env:PRISM_DISABLE_DEEP_DEBUG') -and `
        'Continue' -in @($Global:DebugPreference, $DebugPreference) )
    {
        $deepPrefs['Debug'] = $false
    }

    if( (Test-Path -Path 'env:PRISM_DISABLE_DEEP_VERBOSE') -and `
        'Continue' -in @($Global:VerbosePreference, $VerbosePreference))
    {
        $deepPrefs['Verbose'] = $false
    }

    return $deepPrefs
}
