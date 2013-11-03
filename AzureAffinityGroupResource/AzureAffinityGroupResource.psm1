function Get-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $location,

        [string] $description,
        [string] $label
    )

    $res = @{}
    try
    {
        Set-AzureSubscription -SubscriptionName $subscriptionName

        Write-Verbose ("Searching for Azure Affinity Group '{0}'" -f $name)
        $afGroup = Get-AzureAffinityGroup -name $name

        if (!$afGroup)
        {
            $res += @{ Ensure = "absent" }
        }
        else
        {
            $res += @{
                        Ensure = "present"
                        Name = $afGroup.Name
                        Description = $afGroup.Description
                        Label = $afGroup.Label
                        Location = $afGroup.Location
                    }
        }    
    }
    catch
    {
        $res += @{ Ensure = "absent" }  
    }

    return $res
}

function Test-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $location,

        [string] $description,
        [string] $label
    )

    $currentState = Get-TargetResource @PSBoundParameters

    return ($currentState.ensure -ieq $ensure)
}

function Set-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $location,

        [string] $description,
        [string] $label = $name
    )

    #$currentState = Get-TargetResource @PSBoundParameters
    Set-AzureSubscription -SubscriptionName $subscriptionName

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure Affinity Group"
        Remove-AzureAffinityGroup -name $name
    }
    else
    {
        $PSBoundParameters.Remove('ensure')
        $PSBoundParameters.Remove('subscriptionName')
        Write-Verbose "Creating Azure Affinity Group"
        New-AzureAffinityGroup @PSBoundParameters
    }
}

if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }