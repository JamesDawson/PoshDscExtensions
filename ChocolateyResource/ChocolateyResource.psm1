function Get-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,
        [string] $package,
        [string] $version
    )

    $res = @{}

    # Is Chocolatey already installed?
    if (Test-Path $chocolateyPath)
    {
        $res += @{ IsChocolateyInstalled = $true }

        # Check if the package is already installed
        $versionInfo = & $chocolateyPath Version $package -localOnly

        if ($versionInfo.found -eq 'no version')
        {
            $res += @{ IsInstalled = $false }
        }
        else
        {
            $res += @{ IsInstalled = $true }
            $res += @{ Version = $versionInfo.found }
        }
    }
    else
    {
        $res += @{ IsChocolateyInstalled = $false }
    }

    return $res
}

function Test-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,
        [string] $package,
        [string] $version
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ( !($currentState.IsChocolateyInstalled) )
    {
        Write-Verbose "Chocolatey is not installed"
        return $false
    }

    if ($ensure -ieq "present" -and $currentState.IsInstalled)
    {
        Write-Verbose "Package is already installed"
        return $true
    }

    if ( $ensure -ieq "absent" -and !($currentState.IsInstalled) )
    {
        Write-Verbose "Package is already not installed"
        return $true
    }

    # If we get this far we can assume that we're out of policy
    return $false
}

function Set-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,
        [string] $package,
        [string] $version
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ( !($currentState.IsChocolateyInstalled) )
    {
        _installChocolatey
    }

    if ($ensure -ieq "present")
    {
        & $chocolateyPath install $package
    }
    else
    {
        & $chocolateyPath uninstall $package
    }
}

function _installChocolatey
{
    Write-Verbose "Installing Chocolatey"
    iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
}

# default chocolatey install path
$chocolateyPath = "C:\Chocolatey\chocolateyinstall\chocolatey.ps1"
# attempt to find an existing install path
if ($env:ChocolateyInstall)
{
    $chocolateyPath = "$env:ChocolateyInstall\chocolateyinstall\chocolatey.ps1"
}
