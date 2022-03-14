function Select-Module
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Module,

        [Parameter(Mandatory)]
        [String] $Name,

        [String] $Version,

        [switch] $AllowPrerelease
    )

    process
    {
        if( $Module.Name -ne $Name )
        {
            return
        }

        if( $Version -and $Module.Version -notlike $Version )
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