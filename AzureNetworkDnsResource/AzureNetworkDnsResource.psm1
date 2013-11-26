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

        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerIpAddress,
        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerCloudService,
        [parameter(ParameterSetName = "WithDns", Mandatory = $true)]
        [string] $dnsServerName
    )

    $res = @{}
    Set-AzureSubscription -SubscriptionName $subscriptionName

    $netXml = [xml]((Get-AzureVNetConfig -ea 0).XmlConfiguration)
    $dnsConfig = $netXml.NetworkConfiguration.VirtualNetworkConfiguration.Dns

    $res += @{
                DnsServers = [array]($dnsConfig.DnsServers.DnsServer.name)
                NetConfigXml = $netXml
            }

    Write-Verbose ("Searching for Azure Virtual Network '{0}'" -f $name)
    $net = $netXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.name -ieq $name }
    if ($net.DnsServersRef -and $net.DnsServersRef.DnsServerRef) {
        $res += @{
            NetworkName = $net.Name
            DnsServerRefs = [array]($net.DnsServersRef.DnsServerRef.name)
        }
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

        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerIpAddress,
        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerCloudService,
        [parameter(ParameterSetName = "WithDns", Mandatory = $true)]
        [string] $dnsServerName
    )

    $currentState = Get-TargetResource @PSBoundParameters

    $installed = (($currentState.DnsServers -icontains $dnsServerName) -and ($currentState.DnsServerRefs -icontains $dnsServerName))
    $notInstalled = (($currentState.DnsServers -inotcontains $dnsServerName) -and ($currentState.DnsServerRefs -inotcontains $dnsServerName))
    $partial = (($currentState.DnsServers -icontains $dnsServerName) -xor ($currentState.DnsServerRefs -icontains $dnsServerName))

    if ($ensure -ieq "present" -and ($notInstalled -or $partial)) {
        Write-Verbose "Network DNS: Not fully installed"
        return $false
    }

    if ($ensure -ieq "absent" -and ($installed -or $partial)) {
        Write-Verbose "Network DNS: Not fully removed"
        return $false
    }

    Write-Verbose "Network DNS: All Good!"
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

        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerIpAddress,
        [parameter(ParameterSetName = "WithDns", Mandatory = $false)]
        [string] $dnsServerCloudService,
        [parameter(ParameterSetName = "WithDns", Mandatory = $true)]
        [string] $dnsServerName
    )

    $boundParams = $PSBoundParameters

    $currentState = Get-TargetResource @boundParams

    $netCfgNs = "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"

    if ($ensure -ieq "absent")
    {
        $dnsConfig = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.Dns
        if ($dnsConfig -and $dnsConfig.DnsServers -and $dnsConfig.DnsServers.DnsServer) {
            $dnsServerToRemove = $dnsConfig.DnsServers.DnsServer | ? { $_.name -ieq $dnsServerName }
            if ($dnsServerToRemove) {
                Write-Verbose "Removing Azure Network DNS Server"
                $dnsConfig.DnsServers.RemoveChild($dnsServerToRemove)
            }
        }
    }
    else
    {
        # Apply core network configuration
        Write-Verbose "Updating network configuration"
        $netConfig = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | ? { $_.name -ieq $name }
        
        # Resolve the IP address if a VM is hosting DNS
        if ($dnsServerCloudService) {
            Write-Verbose "Retrieving IP address for the VM running DNS: $dnsServerCloudService"
            $vmDeployment = Get-AzureDeployment -ServiceName $dnsServerCloudService -slot Production -ea 0
            if ($vmDeployment) {
                $dnsServerIpAddress = $vmDeployment.RoleInstanceList.IpAddress

                if (!$dnsServerIpAddress) {
                    throw "Unable to retrieve the IP address for '{0}' - is it deployed yet?"
                }
            }
        }
            
        # Apply DNS configuration
        if ($dnsServerIpAddress) {
            Write-Verbose ("Configuring DNS server '{0}' with IP address '{1}'" -f $dnsServerName, $dnsServerIpAddress)
         
            $dnsServersConfig = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers
            if (!$dnsServersConfig) {
                $dnsConfig = New-XmlElement -doc $currentState.NetConfigXml -name DnsServers -ns $netCfgNs
                $dnsConfig.AppendChild($dnsServersConfig)
            }

            $dnsServerConfig = $currentState.NetConfigXml.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.DnsServer | ? { $_.name -ieq $name }
            if (!$dnsServerConfig) {
                $dnsServerConfig = New-XmlElement -doc $currentState.NetConfigXml -name DnsServer -attributes @{name=$dnsServerName} -ns $netCfgNs
                $dnsServersConfig.AppendChild($dnsServerConfig)
            }            
            $dnsServerConfig.SetAttribute("IPAddress", $dnsServerIpAddress)



            Write-Verbose "Adding DNS server reference"
            $dnsServersRef = $netConfig.DnsServersRef
            if (!$dnsServersRef) {
                $dnsServersRef = New-XmlElement -doc $currentState.NetConfigXml -name "DnsServersRef" -ns $netCfgNs
                $netConfig.AppendChild($dnsServersRef)
            }

            $dnsServerRef = $netConfig.DnsServersRef.DnsServerRef | ? { $_ -and ($_.name -ieq $dnsServerName) }
            if (!$dnsServerRef) {
                $dnsServerRef = New-XmlElement -doc $currentState.NetConfigXml -name "DnsServerRef" -attributes @{name=$dnsServerName} -ns $netCfgNs
                $DnsServersRef.AppendChild($dnsServerRef)
            }
        }
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
        NewDns = <DnsServers><DnsServer name="{0}" IPAddress="{1}"/></DnsServers>
        NewDnsRef = <DnsServerRef name="{0}"/>
'@
}

if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }