function Get-TargetResource 
{
    [CmdletBinding()]
    param 
    (
        [ValidateSet("Present","Absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,
        [parameter(Mandatory = $true)]
        [string] $destContainer,
        [parameter(Mandatory = $true)]
        [string] $diskName,

        [ValidateSet("","windows","linux")]
        [string] $os
    )

    Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccountName $storageAccountName
    #Select-AzureSubscription $subscriptionName

    $azureDisk = Get-AzureDisk -DiskName $diskName -ea 0

    if ($azureDisk) {
        $res += @{
            Ensure = $true
            Uri = $azureDisk.MediaLink.AbsoluteUri
        }
    }
    else {
        $res += @{ Ensure = $false }
    }

    return $res
}

function Test-TargetResource 
{
    [CmdletBinding()]
    param 
    (
        [ValidateSet("Present","Absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,
        [parameter(Mandatory = $true)]
        [string] $destContainer,
        [parameter(Mandatory = $true)]
        [string] $diskName,

        [ValidateSet("","windows","linux")]
        [string] $os
    )

    $currentState = Get-TargetResource @PSBoundParameters

    return ($currentState.ensure -ieq $ensure)
}

function Set-TargetResource 
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param 
    (        
        [ValidateSet("Present","Absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountName,
        [parameter(Mandatory = $true)]
        [string] $storageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,
        [parameter(Mandatory = $true)]
        [string] $destContainer,
        [parameter(Mandatory = $true)]
        [string] $diskName,

        [ValidateSet("","windows","linux")]
        [string] $os
    )

    $destContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    if ($ensure -ieq "present") {
        if ($pscmdlet.ShouldProcess("Creating the Azure Disk object '$diskName'")) {
            
            $clonedVhdUri = _cloneVhd $sourceVhdBlobUri $destContext $destContainer $diskName            

            $azureDisk = Get-AzureDisk -DiskName $diskName -ea 0
            if ( !($azureDisk) )
            {
                $osAzureDisk = Add-AzureDisk -DiskName $diskName -MediaLocation $clonedVhdUri -OS $os
            }
        }
    }
}


function _createContainer {
    param
    (
        $destContext,
        $containerName
    )

    if ( !(Get-AzureStorageContainer -Name $containerName -Context $destContext -ea 0) )
    {
        try {
            New-AzureStorageContainer -Name $containerName -Context $destContext
        } catch {
            throw ("There was a problem creating the container: '{0}'" -f $containerName)
        }
    }
}

function _cloneVhd {
    param
    (
        $sourceVhdBlobUri,
        $destContext,
        $destContainerName,
        $diskName
    )

    _createContainer $destContext $destContainerName

    $blob = Get-AzureStorageBlob -Blob ("{0}.vhd" -f $diskName) -Container $destContainerName -Context $destContext -ea 0
    if ( !($blob) )
    {
        $blob = Start-AzureStorageBlobCopy -srcUri $sourceVhdBlobUri `
                                             -DestContainer $destContainerName `
                                             -DestBlob ("{0}.vhd" -f $diskName) `
                                             -DestContext $destContext

        $res = $blob | Get-AzureStorageBlobCopyState
        if (!$res)
        {
            throw "There was an error cloning the VHD"
        }
    }
    else
    {
        Write-Verbose ("The cloned VHD already exists: {0}" -f $blob.Name)
    }

    return ("{0}{1}/{2}.vhd" -f $blob.Context.BlobEndPoint, $destContainerName, $diskName)
}
<#


$vmConfig = New-AzureVMConfig -Name $name -DiskName $osAzureDisk.Label -InstanceSize $instanceSize | `
            Set-AzureSubnet $subnets | `
            New-AzureVM -ServiceName $serviceName -VNetName $networkName -AffinityGroup $affinityGroup -WaitForBoot:$waitForBoot

#get-azurevm valvmalm001 | add-azureendpoint -Name 'Remote Desktop' -Protocol TCP -LocalPort 3389 -PublicPort 50111 | Update-AzureVM

$ErrorActionPreference = "Continue"

#>

# Sometimes the installation path of the Azure module does not get added to the
# PSModulePath environment variable
if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }
