function Get-TargetResource 
{
    [CmdletBinding()]
    param 
    (
    )

    $currentTimezone = & tzutil.exe /g

    return @{ Timezone = $currentTimezone }
}

function Test-TargetResource 
{
    [CmdletBinding()]
    param 
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$timezone        
    )

    [bool]$result = (& tzutil.exe /g).Trim() -ieq $timezone
    return $result
}

function Set-TargetResource 
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param 
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$timezone         
    )

    if ($pscmdlet.ShouldProcess("Setting the specified Timezone"))
    {
        & tzutil.exe /s "$timezone"
    }
}




