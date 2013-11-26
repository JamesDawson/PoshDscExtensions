function Get-TargetResource 
{
    [CmdletBinding()]
    param 
    (
        [ValidateSet("Present","Absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,

        [parameter(Mandatory = $false)]
        [string] $sourceStorageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,

        [parameter(Mandatory = $true)]
        [string] $destStorageAccountName,
        [parameter(Mandatory = $true)]
        [string] $destStorageAccountKey,
        [parameter(Mandatory = $true)]
        [ValidatePattern("^[a-z0-9](([a-z0-9\-[^\-])){1,61}[a-z0-9]$")]
        [string] $destContainer,
        
        [parameter(Mandatory = $true)]
        [string] $diskName,

        [ValidateSet("","windows","linux")]
        [string] $os
    )

    Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccountName $destStorageAccountName

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

        [parameter(Mandatory = $false)]
        [string] $sourceStorageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,

        [parameter(Mandatory = $true)]
        [string] $destStorageAccountName,
        [parameter(Mandatory = $true)]
        [string] $destStorageAccountKey,
        [parameter(Mandatory = $true)]
        [ValidatePattern("^[a-z0-9](([a-z0-9\-[^\-])){1,61}[a-z0-9]$")]
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

        [parameter(Mandatory = $false)]
        [string] $sourceStorageAccountKey,
        [parameter(Mandatory = $true)]
        [string] $sourceVhdBlobUri,

        [parameter(Mandatory = $true)]
        [string] $destStorageAccountName,
        [parameter(Mandatory = $true)]
        [string] $destStorageAccountKey,
        [parameter(Mandatory = $true)]
        [ValidatePattern("^[a-z0-9](([a-z0-9\-[^\-])){1,61}[a-z0-9]$")]
        [string] $destContainer,
        
        [parameter(Mandatory = $true)]
        [string] $diskName,

        [ValidateSet("","windows","linux")]
        [string] $os
    )
    
    if ($sourceStorageAccountKey) {
        $sourceContext = _deriveSourceStorageContext $sourceVhdBlobUri $sourceStorageAccountKey
    }
    $destContext = New-AzureStorageContext -StorageAccountName $destStorageAccountName -StorageAccountKey $destStorageAccountKey

    if ($ensure -ieq "present") {
        if ($pscmdlet.ShouldProcess("Creating the Azure Disk object '$diskName'")) {
            
            $clonedVhdUri = _cloneVhd $sourceVhdBlobUri $destContext $destContainer $diskName $sourceContext

            $azureDisk = Get-AzureDisk -DiskName $diskName -ea 0
            if ( !($azureDisk) )
            {
                Write-Verbose "Registering VHD as an Azure disk"
                $azureDisk = Add-AzureDisk -DiskName $diskName -MediaLocation $clonedVhdUri -OS $os
            }
        }
    }
}

function _deriveSourceStorageContext {
    param
    (
        [uri]$sourceBlobUri,
        $storageAccountKey
    )

    $storageAccountName = ($sourceBlobUri.Host.Split("."))[0]

    $context = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    return $context
}

function _createContainer {
    param
    (
        $storageContext,
        $containerName
    )

    Write-Verbose "Checking for the container: $containerName"
    if ( !(Get-AzureStorageContainer -Name $containerName -Context $storageContext -ea 0) )
    {
        try {
            Write-Verbose "Creating the container: $containerName"
            New-AzureStorageContainer -Name $containerName -Permission Off -Context $storageContext

            while( !(Get-AzureStorageContainer -Name $containerName -Context $storageContext -ea 0) )
            {
                Write-Verbose "Waiting for container to be created..."
                sleep -Seconds 5
            }
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
        $diskName,
        $sourceContext
    )

    $newContainer = _createContainer $destContext $destContainerName

    $blob = Get-AzureStorageBlob -Blob ("{0}.vhd" -f $diskName) -Container $destContainerName -Context $destContext -ea 0
    if ( !($blob) )
    {
        if ($sourceContext) {
            $blob = Start-AzureStorageBlobCopy -srcUri $sourceVhdBlobUri `
                                                 -srcContext $sourceContext `
                                                 -DestContainer $destContainerName `
                                                 -DestBlob ("{0}.vhd" -f $diskName) `
                                                 -DestContext $destContext
        }
        else {
            $blob = Start-AzureStorageBlobCopy -srcUri $sourceVhdBlobUri `
                                                 -DestContainer $destContainerName `
                                                 -DestBlob ("{0}.vhd" -f $diskName) `
                                                 -DestContext $destContext
        }

        # A cross-stamp blob copy will not be instantaneous, so we may need to wait
        While( ($blob | Get-AzureStorageBlobCopyState).Status -eq "Pending" ) {
            Write-Verbose "Waiting for VHD to be copied..."
            Start-Sleep 10
        }
    }
    else
    {
        Write-Verbose ("The cloned VHD already exists: {0}" -f $blob.Name)
    }

    return ("{0}{1}/{2}.vhd" -f $blob.Context.BlobEndPoint, $destContainerName, $diskName)
}

# Sometimes the installation path of the Azure module does not get added to the
# PSModulePath environment variable
if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }
