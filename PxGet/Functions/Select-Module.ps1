function Select-Module
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [PSCustomObject] $Module,

        [Parameter(Mandatory)]
        [String] $Name,

        [Parameter(Mandatory)]
        [String] $Version,  

        [switch] $AllowPrerelease
    )

    process
    {
        if( $Module.Name -ne $Name -or $Module.Version -notlike $Version )
        {
            return
        }

        if( $AllowPrerelease )
        {
            return $Module
        }

        [Version]$moduleVersion = $null
        if( [Version]::TryParse($Module.Version, [ref]$moduleVersion) )
        {
            return $Module
        }
    }
}