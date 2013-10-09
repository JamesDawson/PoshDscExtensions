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
        [string] $location,
        [parameter(Mandatory = $true)]
        [string] $adminUsername,
        [parameter(Mandatory = $true)]
        [string] $adminPassword,
        [parameter(Mandatory = $true)]
        [string] $image,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [array]  $dataDisks,
        [bool] $waitForBoot
    )

    try
    {
        $res = @{}

        _initialiseAzurePublisherSettings $subscriptionName $storageAccountName

        Write-Verbose "Get-AzureVm"
        $vm = Get-AzureVM -ServiceName $serviceName -Name $name
        Write-Verbose "Get-AzureService"
        $svc = Get-AzureService -ServiceName $serviceName -ea 0
        Write-Verbose "Get-AzureDeployment"
        $dep = Get-AzureDeployment -ServiceName $serviceName -ea 0

        if ($vm)
        {
            $res += @{
                        Name = $vm.Name;
                        ServiceName = $vm.ServiceName;
                        Location = $svc.Location;
                        Status = $vm.Status;
                    }

            # VM States: running, readyvmrole, stoppedvm
            if ($vm.Status -ieq "running") { $res += @{ Ensure = "running" } }
            elseif ($vm.Status -ieq "readyvmrole") { $res += @{ Ensure = "stopped" } }
            else { $res += @{ Ensure = "present" } }
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
        [string] $location,
        [parameter(Mandatory = $true)]
        [string] $adminUsername,
        [parameter(Mandatory = $true)]
        [string] $adminPassword,
        [parameter(Mandatory = $true)]
        [string] $image,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [array]  $dataDisks,
        [bool] $waitForBoot
    )

    $currentState = Get-TargetResource @PSBoundParameters

    # VM exists when it shouldn't
    if ($ensure -ieq "absent" -and $currentState)
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
    if ($ensure -ieq "running" -and $currentState.State -ine "ReadyVmRole")
    {
        Write-Verbose "VM is not running"
        return $false
    }

    # VM is not stopped when it should
    if ($ensure -ieq "stopped" -and $currentState.State -ine "StoppedVm")
    {
        Write-Verbose "VM is not stopped"
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
        [string] $location,
        [parameter(Mandatory = $true)]
        [string] $adminUsername,
        [parameter(Mandatory = $true)]
        [string] $adminPassword,
        [parameter(Mandatory = $true)]
        [string] $image,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,

        [array]  $dataDisks,
        [bool] $waitForBoot
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure VM"
        Remove-AzureVm -ServiceName $serviceName -Name $name -Force -Verbose:$VerbosePreference
    }

    if ($currentState.ensure -ieq "absent" -and $ensure -ine "absent")
    {
        Write-Verbose "Configuring new Azure VM"
        $vmConfig = New-AzureVMConfig -Name $name -InstanceSize $instanceSize -Image $image
        $vmConfig | Add-AzureProvisioningConfig -Windows -AdminUserName $adminUsername -Password $adminPassword
        Write-Verbose "Provisioning new Azure VM"
        $opResult = $vmConfig | New-AzureVM -ServiceName $serviceName -Location $location -WaitForBoot:$waitForBoot
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
            Write-Verbose "Waiting for new VM to become available (so it can be stopped)"
            while( (Get-AzureVm -ServiceName $serviceName -Name $name).Status -ieq "provisioning" )
            {
                sleep -Seconds 10
            }
        }

        Write-Verbose "Stopping Azure VM"
        Stop-AzureVm -ServiceName $serviceName -Name $name
    }
}

Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false