param
(
)

$pullServerUnc = "C:\ProgramData\PSDSCPullServer\Modules"

$resources = @(
                "$pwd\AzurePublishingProfileResource",
                "$pwd\AzureVmResource",
                "$pwd\TimezoneResource"
            )

Write-Host "Publishing DSC Resource Providers"
& "$pwd\..\publish.ps1" -resources $resources -pullServerUnc $pullServerUnc -updatePsProviders
