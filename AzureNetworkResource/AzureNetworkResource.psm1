function Get-TargetResource
{
    [CmdletBinding()]
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
            $res += @{
                        Ensure = "absent"
                        NetConfigXml = $netXml
                    }
        }
        else
        {
            $res += @{
                        Ensure = "present"
                        Name = $net.Name
                        AffinityGroup = $net.AffinityGroup
                        AddressSpace = $net.AddressSpace.AddressPrefix                        
                        NetConfigXml = $netXml
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
    [CmdletBinding()]
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
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ($currentState.ensure -ne $ensure) {
        # needs installing or removing
        Write-Verbose "Network: Current=$($currentState.ensure); Desired=$ensure"
        return $false
    }
    elseif ($ensure -ieq "present") {
        if ( ($currentState.AffinityGroup -ine $affinityGroup) -or `
                ($currentState.AddressSpace -ine $addressSpace) ) {
            return $false
        }
    }

    Write-Verbose "Network: All Good!"
    return $true
}

function Set-TargetResource
{
    [CmdletBinding()]
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
    )

    $boundParams = $PSBoundParameters

    $currentState = Get-TargetResource @boundParams

    $netCfgNs = "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure Network"
        $netToRemove = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.name -ieq $name }
        if ($netToRemove) {
            $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.RemoveChild($netToRemove) | Out-Null
        }
    }
    else
    {
        if ($currentState.ensure -ieq "absent") {
            Write-Verbose "Creating network configuration"
            $newNetConfig = New-XmlElement -doc $currentState.NetConfigXml -name "VirtualNetworkSite" -attributes @{name=$name; AffinityGroup=$affinityGroup} -ns $netCfgNs
            $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.AppendChild($newNetConfig)
        }

        # Apply core network configuration
        Write-Verbose "Updating network configuration"
        $netConfig = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.name -ieq $name }

        $netConfig.InnerXml = $templates.NewNetwork -f $addressSpace, $subnetName        
    }

    # Update the network config in Azure
    Write-Verbose "Applying network configuration changes"
    $file = [IO.Path]::GetTempFileName() -replace "\.tmp",".netcfg"
    $currentState.NetConfigXml.Save($file)

    Set-AzureVNetConfig -configurationPath $file
    rm $file
}

function New-XmlElement
{
    param
    (
        [xml] $doc,
        [string] $name,
        [string] $ns,
        [string] $value,
        [hashtable] $attributes = @{},
        [xml.xmlelement[]] $children = @(),

        [Parameter(ValueFromPipeline=$true)]
        [xml.xmlelement] $parent
    )

    $newNode = $doc.CreateElement($name, $ns)
    $newNode.InnerText = $value
    $attributes.Keys | % {
        $newNode.SetAttribute($_, $attributes[$_])
    }

    $children | % { $newNode.AppendChild($_) }

    return $newNode
}

$templates = DATA {
    ConvertFrom-StringData -stringdata @'
        NewNetwork = <AddressSpace><AddressPrefix>{0}</AddressPrefix></AddressSpace><Subnets><Subnet name="{1}"><AddressPrefix>{0}</AddressPrefix></Subnet></Subnets>
'@
}

if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }