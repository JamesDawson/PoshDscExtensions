param
(
    [switch] $updateResources,
    [switch] $updatePsProviders
)

$pullServerRoot = "C:\ProgramData\PSDSCPullServer"

$resources = @()
if ($updateResources)
{
    $resources = @(
                "$pwd\AzurePublishingProfileResource",
                "$pwd\AzureVmResource",
                "$pwd\TimezoneResource",
                "$pwd\ChocolateyResource"
            )
}

Write-Host "Publishing DSC Resource Providers"
& "$pwd\..\publish.ps1" -resources $resources -pullServerRoot $pullServerRoot -updatePsProviders:$updatePsProviders
