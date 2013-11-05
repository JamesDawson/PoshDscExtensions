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
        [string] $addressSpace

        #[parameter(Mandatory = $false)]
        #[string] $subnetName,
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
        [string] $addressSpace

        #[parameter(Mandatory = $false)]
        #[string] $subnetName,
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
        [string] $addressSpace

        #[parameter(Mandatory = $false)]
        #[string] $subnetName,
        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
    )

    #$currentState = Get-TargetResource @PSBoundParameters
    Set-AzureSubscription -SubscriptionName $subscriptionName

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure Network - NOT IMPLEMENTED"
        #Remove-AzureVNetConfig
    }
    else
    {
        $PSBoundParameters.Remove('ensure')
        $PSBoundParameters.Remove('subscriptionName')

        Write-Verbose "Generating network configuration"
        $netXmlFile = _generateVirtualNetworkConfiguration @PSBoundParameters

        Write-Verbose "Configuring Azure network"
        Set-AzureVNetConfig -configurationPath $netXmlFile
        rm $netXmlFile
    }
}

function _generateVirtualNetworkConfiguration
{
    param
    (
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $affinityGroup,
        [parameter(Mandatory = $true)]
        [string] $addressSpace

        #[parameter(Mandatory = $false)]
        #[string] $subnetName,
        #[parameter(Mandatory = $false)]
        #[string] $subnetAddressPrefix
    )

    $netConfigXml = (@"
<NetworkConfiguration xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                      xmlns="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration">
  <VirtualNetworkConfiguration>
    <Dns>
      <!--<DnsServers>
        <DnsServer name="foo" IPAddress="" />
      </DnsServers>-->
    </Dns>
    <VirtualNetworkSites>
      <VirtualNetworkSite name="{0}" AffinityGroup="{1}">
        <AddressSpace>
          <AddressPrefix>{2}</AddressPrefix>
        </AddressSpace>
        <Subnets>
          <Subnet name="Subnet-{0}-1">
            <AddressPrefix>{2}</AddressPrefix>
          </Subnet>
        </Subnets>
      </VirtualNetworkSite>
    </VirtualNetworkSites>
  </VirtualNetworkConfiguration>
</NetworkConfiguration>
"@ -f $name, $affinityGroup, $addressSpace)

    $file = [IO.Path]::GetTempFileName() -replace "\.tmp",".netcfg"
    Set-Content -Path $file -Value $netConfigXml -Encoding UTF8

    return $file
}

if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }