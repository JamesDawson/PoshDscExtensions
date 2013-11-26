param
(
    [switch] $updateResources,
    [switch] $updatePsProviders
)

$pullServerRoot = "$pwd\_PSDSCPullServer"
if ( !(Test-Path "$pullServerRoot\Modules") ) { md "$pullServerRoot\Modules" | Out-Null }
if ( !(Test-Path "$pullServerRoot\Configuration") ) { md "$pullServerRoot\Configuration" | Out-Null }

$resources = @()
if ($updateResources)
{
    $resources = @(
                "$pwd\AzurePublishingProfileResource",
                "$pwd\AzureVmResource",
                "$pwd\AzureAffinityResource",
                "$pwd\AzureNetworkResource",
                "$pwd\AzureNetworkDnsResource",
                "$pwd\CloneAzureVhdResource",
                "$pwd\AzureVmResource",
                "$pwd\TimezoneResource",
                "$pwd\ChocolateyResource"
            )
}

Write-Host "Publishing DSC Resource Providers"
& .\publish.ps1 -resources $resources -pullServerRoot $pullServerRoot -updatePsProviders:$updatePsProviders
