function Get-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,

        [parameter(Mandatory = $true)]
        [string] $subscriptionId,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $base64Certificate,

        [string] $publishMethod = "AzureServiceManagementAPI",
        [string] $url = "https://management.core.windows.net"
    )

    $res = @{}
    try
    {
        Write-Verbose ("Searching for Azure Subscription '{0}'" -f $subscriptionName)
        $subs = Get-AzureSubscription $subscriptionName -ea 0

        if (!$subs)
        {
            $res += @{ Ensure = "absent" }
        }
        else
        {
            $res += @{ Ensure = "present" }
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
        [string] $subscriptionId,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $base64Certificate,

        [string] $publishMethod = "AzureServiceManagementAPI",
        [string] $url = "https://management.core.windows.net"
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
        [string] $subscriptionId,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $base64Certificate,

        [string] $publishMethod = "AzureServiceManagementAPI",
        [string] $url = "https://management.core.windows.net"
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ($ensure -ieq "absent")
    {
        Write-Verbose "Removing Azure Subscription"
        Remove-AzureSubscription -subscriptionName $subscriptionName
    }
    else
    {
        $PSBoundParameters.Remove('ensure')
        Write-Verbose "Generating publishing profile"
        $appXmlFile = _generatePublishingProfile @PSBoundParameters

        Write-Verbose "Importing publishing profile"
        Import-AzurePublishSettingsFile $appXmlFile
        rm $appXmlFile
    }
}

function _generatePublishingProfile
{
    param
    (
        [parameter(Mandatory = $true)]
        [string] $subscriptionId,

        [parameter(Mandatory = $true)]
        [string] $subscriptionName,
        [parameter(Mandatory = $true)]
        [string] $base64Certificate,

        [parameter(Mandatory = $true)]
        [string] $publishMethod,
        [parameter(Mandatory = $true)]
        [string] $url
    )

    $profileXml = (@"
<?xml version="1.0" encoding="utf-8"?>
<PublishData>
  <PublishProfile
    PublishMethod="{0}"
    Url="{1}"
    ManagementCertificate="{2}">
    <Subscription
      Id="{3}"
      Name="{4}" />
  </PublishProfile>
</PublishData>
"@ -f $publishMethod, $url, $base64Certificate, $subscriptionId, $subscriptionName)

    $file = [IO.Path]::GetTempFileName() -replace "\.tmp",".PublishSettings"
    Set-Content -Path $file -Value $profileXml -Encoding UTF8

    return $file
}

if ( !(Get-Module Azure) ) { Import-Module 'C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure' -Verbose:$false }