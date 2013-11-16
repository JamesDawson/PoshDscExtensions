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
        [string] $affinityGroup,
        [parameter(Mandatory = $true)]
        [string] $addressSpace,
        [parameter(Mandatory = $true)]
        [string] $subnetName

        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
    )

    $res = @{}
    try
    {
        Set-AzureSubscription -SubscriptionName $subscriptionName

        Write-Verbose ("Searching for Azure Virtual Network '{0}'" -f $name)
        $netXml = [xml]((Get-AzureVNetConfig -ea 0).XmlConfiguration)
        $net = $netXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.name -ieq $name }

        if (!$net)
        {
            $res += @{ Ensure = "absent" }
        }
        else
        {
            $res += @{
                        Ensure = "present"
                        Name = $net.Name
                        AffinityGroup = $net.AffinityGroup
                        AddressSpace = $net.AddressSpace.AddressPrefix
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
        [string] $affinityGroup,
        [parameter(Mandatory = $true)]
        [string] $addressSpace,
        [parameter(Mandatory = $true)]
        [string] $subnetName

        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
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
        [string] $affinityGroup,
        [parameter(Mandatory = $true)]
        [string] $addressSpace,
        [parameter(Mandatory = $true)]
        [string] $subnetName

        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
    )

    #$currentState = Get-TargetResource @PSBoundParameters
    Set-AzureSubscription -SubscriptionName $subscriptionName

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure Network"
        $netXmlFile = _removeVirtualNetworkConfiguration $name
    }
    else
    {
        $PSBoundParameters.Remove('ensure')
        $PSBoundParameters.Remove('subscriptionName')

        Write-Verbose "Creating network configuration"
        $netXmlFile = _addVirtualNetworkConfiguration @PSBoundParameters
    }

    # Update the network config in Azure
    Write-Verbose "Applying network configuration changes"
    Set-AzureVNetConfig -configurationPath $netXmlFile
    rm $netXmlFile

}

function _addVirtualNetworkConfiguration
{
    param
    (
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $affinityGroup,
        [parameter(Mandatory = $true)]
        [string] $addressSpace,
        [parameter(Mandatory = $true)]
        [string] $subnetName

        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
    )

    # Retrieve the current network configuration
    [xml]$currentNetConfig = (Get-AzureVNetConfig).XmlConfiguration

    # Create a new VirtualNetworkSite element
    $newNet = ($currentNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | Select -Last 1).Clone()

    # Configure the new network
    $newNet.Name = $name
    $newNet.AffinityGroup = $affinityGroup
    $newNet.AddressSpace.AddressPrefix = $addressSpace
    $newNet.Subnets.Subnet.Name = $subnetName
    $newNet.Subnets.Subnet.AddressPrefix = $addressSpace

    $currentNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.AppendChild($newNet) | Out-Null

    $file = [IO.Path]::GetTempFileName() -replace "\.tmp",".netcfg"
    $currentNetConfig.Save($file)
    return $file
}

function _removeVirtualNetworkConfiguration
{
    param
    (
        [parameter(Mandatory = $true)]
        [string] $name
    )

    # Retrieve the current network configuration
    [xml]$currentNetConfig = (Get-AzureVNetConfig).XmlConfiguration

    # Locate the network to remove
    $netToRemove = $currentNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.Name -ieq $name }

    # Remove the network
    $currentNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.RemoveChild($netToRemove) | Out-Null

    $file = [IO.Path]::GetTempFileName() -replace "\.tmp",".netcfg"
    $currentNetConfig.Save($file)
    return $file
}


if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }