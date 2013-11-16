function _initialiseAzurePublisherSettings
{
    param
    (
        $subscriptionName,
        $storageAccountName
    )

    Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccountName
}

function Get-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present","Absent","Running","Stopped")]
        [string] $ensure,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $serviceName,
        [parameter(Mandatory = $true)]
        [string] $instanceSize,
        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminUsername,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminPassword,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $baseImage,
        [Parameter(ParameterSetName="FromImage")]
        $enableWinRMHttp = $false,
        
        [Parameter(ParameterSetName="FromVhd", Mandatory=$true)]
        [string] $osDiskName,

        [string] $location = "",
        [string] $affinityGroup = "",
        [string] $networkName,
        [string[]] $subnets,

        [array] $dataDisks,
        [bool] $waitForBoot,
        [bool] $deleteDisksOnRemove
    )

    try
    {
        $res = @{}

        _initialiseAzurePublisherSettings $subscriptionName $storageAccountName

        Write-Verbose "Get-AzureVm"
        $vm = Get-AzureVM -ServiceName $serviceName -Name $name -ea 0
        Write-Verbose "Get-AzureService"
        $svc = Get-AzureService -ServiceName $serviceName -ea 0
        Write-Verbose "Get-AzureDeployment"
        $dep = Get-AzureDeployment -ServiceName $serviceName -ea 0

        if ($vm -or $svc)
        {
            $res += @{
                        Name = $vm.Name;
                        ServiceName = $svc.ServiceName;
                        Location = $svc.Location;
                        Status = $vm.InstanceStatus;
                    }

            # VM States: running, readyvmrole, stoppedvm
            if ($vm.InstanceStatus -ieq "readyrole") { Write-Verbose "VM Running"; $res += @{ Ensure = "running" } }
            elseif ($vm.InstanceStatus -ieq "StoppedDeallocated") { Write-Verbose "VM Stopped"; $res += @{ Ensure = "stopped" } }
            elseif (!$vm) { Write-Verbose "Service created, but no VM"; $res += @{ Ensure = "absent" } }
            else { Write-Verbose "VM State: '$($vm.InstanceStatus)'"; Write-Verbose "CloudService State: '$($svc.Status)'"; $res += @{ Ensure = "present" } }

            if ($vm)
            {
                $res += @{
                            OsDiskName = $vm.VM.OSVirtualHardDisk.DiskName
                        }
            }
        }
        else
        {
            $res += @{ Ensure = "absent" }
        }
    }
    catch
    {
        Write-Verbose "Exception during Get-TargetResource"
        throw
    }

    return $res
}

function Test-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present","Absent","Running","Stopped")]
        [string] $ensure,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $serviceName,
        [parameter(Mandatory = $true)]
        [string] $instanceSize,
        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminUsername,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminPassword,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $baseImage,
        [Parameter(ParameterSetName="FromImage")]
        $enableWinRMHttp = $false,
        
        [Parameter(ParameterSetName="FromVhd", Mandatory=$true)]
        [string] $osDiskName,

        [string] $location = "",
        [string] $affinityGroup = "",
        [string] $networkName,
        [string[]] $subnets,

        [array] $dataDisks,
        [bool] $waitForBoot,
        [bool] $deleteDisksOnRemove
    )

    $currentState = Get-TargetResource @PSBoundParameters

    # VM exists when it shouldn't
    if ($ensure -ieq "absent" -and $currentState.ensure -ine "absent")
    {
        Write-Verbose "VM exists"
        return $false
    }
    elseif ($ensure -ieq "absent")
    {
        return $true
    }
    
    # VM does not exist when it should
    if ($currentState.Name -ine $name -or $currentState.ServiceName -ine $serviceName)
    {
        Write-Verbose "VM does not exist"
        return $false
    }

    # VM is not when running when it should
    if ($ensure -ieq "running" -and $currentState.Ensure -ine "running")
    {
        Write-Verbose ("VM is not running - current state: {0}" -f $currentState.Ensure)
        return $false
    }

    # VM is not stopped when it should
    if ($ensure -ieq "stopped" -and $currentState.Ensure -ine "stopped")
    {
        Write-Verbose ("VM is not stopped - current state: {0}" -f $currentState.Ensure)
        return $false
    }

    # At this point we have a VM and need to check its configuration
    if (
            $currentState.Name -ine $name `
                -or $currentState.ServiceName -ine $serviceName
       )
    {
        Write-Verbose "VM has incorrect configuration"
        return $false
    }

    return $true
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present","Absent","Running","Stopped")]
        [string] $ensure,
        [parameter(Mandatory = $true)]
        [string] $name,
        [parameter(Mandatory = $true)]
        [string] $serviceName,
        [parameter(Mandatory = $true)]
        [string] $instanceSize,
        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminUsername,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $adminPassword,
        [Parameter(ParameterSetName="FromImage", Mandatory=$true)]
        $baseImage,
        [Parameter(ParameterSetName="FromImage")]
        $enableWinRMHttp = $false,
        
        [Parameter(ParameterSetName="FromVhd", Mandatory=$true)]
        [string] $osDiskName,

        [string] $location = "",
        [string] $affinityGroup = "",
        [string] $networkName,
        [string[]] $subnets,

        [array] $dataDisks,
        [bool] $waitForBoot,
        [bool] $deleteDisksOnRemove
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure VM"
        Remove-AzureVm -ServiceName $serviceName -Name $name
        Remove-AzureService -ServiceName $serviceName -Force

        if ($deleteDisksOnRemove)
        {
            while ( (Get-AzureDisk -DiskName $currentState.OsDiskName).AttachedTo -ne $null ) {
                Write-Verbose "Waiting for VM role to detach from disk before removing it..."
                sleep -Seconds 10
            }
            Remove-AzureDisk -DiskName $currentState.OsDiskName -DeleteVHD
        }
    }

    if ($currentState.ensure -ieq "absent" -and $ensure -ine "absent")
    {
        Write-Verbose "Configuring new Azure VM"

        # Configure the VM based on whether we're using an Image or VHD
        if ($PSCmdlet.ParameterSetName -ieq "FromVhd") {
            $vmConfig = New-AzureVMConfig -Name $name -DiskName $osDiskName -InstanceSize $instanceSize | `
                            Set-AzureSubnet $subnets
        }
        else {
            $vmConfig = New-AzureVMConfig -Name $name -InstanceSize $instanceSize -Image $image | `
                            Add-AzureProvisioningConfig -Windows -AdminUserName $adminUsername -Password $adminPassword -EnableWinRMHttp:$enableWinRMHttp | `
                            Set-AzureSubnet $subnets
        }

        Write-Verbose "Provisioning new Azure VM"

        # Recent versions of the Azure Powershell tools make the 'Location' and 'AffinityGroup'
        # parameters mutually exclusive, so we need to code around this
        if ($affinityGroup) {
            $opResult = $vmConfig | New-AzureVM -ServiceName $serviceName -VNetName $networkName -AffinityGroup $affinityGroup -WaitForBoot:$waitForBoot
            
            # For VMs from VHD we need to enable RDP access
            Write-Verbose "Enabling public RDP endpoint on port 50111 for $name"
            Get-AzureVm -Name $name -ServiceName $serviceName | Add-AzureEndpoint -Name 'Remote Desktop' -Protocol TCP -LocalPort 3389 -PublicPort 50111 | Update-AzureVM
        }
        elseif ($location) {
            $opResult = $vmConfig | New-AzureVM -ServiceName $serviceName -Location $location -WaitForBoot:$waitForBoot
        }
        else {
            throw "You must specify an Affinity Group or Location for the new Azure VM"
        }
    }

    if ($currentState.ensure -ieq "stopped" -and $ensure -ieq "running")
    {
        Write-Verbose "Starting Azure VM"
        Start-AzureVm -ServiceName $serviceName -Name $name
    }

    if ($ensure -ieq "stopped")
    {
        # If we've just create a new VM then wait for it to boot
        if ($currentState.ensure -ieq "absent" -and $ensure -ine "absent")
        {
            Write-Verbose "TODO: Waiting for new VM to become available (so it can be stopped)"
            #while( (Get-AzureVm -ServiceName $serviceName -Name $name).Status -ieq "provisioning" )
            #{
            #    sleep -Seconds 10
            #}
        }

        Write-Verbose "Stopping Azure VM"
        Stop-AzureVm -ServiceName $serviceName -Name $name -Force
    }
}

# Sometimes the installation path of the Azure module does not get added to the
# PSModulePath environment variable
if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }