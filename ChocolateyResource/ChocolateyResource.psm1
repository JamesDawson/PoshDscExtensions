function Get-TargetResource
{
    param
    (
        [ValidateSet("present","absent")]
        [string] $ensure,
        [parameter(Mandatory = $true)]
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
        [parameter(Mandatory = $true)]
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
        [parameter(Mandatory = $true)]
        [string] $package,
        [string] $version
    )

    $currentState = Get-TargetResource @PSBoundParameters

    if ( !($currentState.IsChocolateyInstalled) )
    {
        Write-Verbose "ChocolateyResource: Before _installChocolatey"
        _installChocolatey
        Write-Verbose "ChocolateyResource: After _installChocolatey"
    }

    if ($ensure -ieq "present")
    {
        Write-Verbose "ChocolateyResource: Before installing Chocolatey package"
        & $chocolateyPath install $package  | Select-WriteHost | Out-Null
        Write-Verbose "ChocolateyResource: After installing Chocolatey package"
    }
    else
    {
        & $chocolateyPath uninstall $package | Select-WriteHost | Out-Null
    }
}

function _installChocolatey
{
    Write-Verbose "Installing Chocolatey"
    $chocoUrl = 'http://10.0.0.5:8080/installChocolatey.ps1.txt'
    #$chocoUrl = 'https://chocolatey.org/install.ps1'
    
    iex ((new-object net.webclient).DownloadString($chocoUrl)) | Select-WriteHost | Out-Null
}


function Select-WriteHost
{
   [CmdletBinding(DefaultParameterSetName = 'FromPipeline')]
   param(
     [Parameter(ValueFromPipeline = $true, ParameterSetName = 'FromPipeline')]
     [object] $InputObject,
 
     [Parameter(Mandatory = $true, ParameterSetName = 'FromScriptblock', Position = 0)]
     [ScriptBlock] $ScriptBlock,
 
     [switch] $Quiet
   )
 
   begin
   {
     function Cleanup
     {
       # clear out our proxy version of write-host
       remove-item function:write-host -ea 0
     }
 
     function ReplaceWriteHost([switch] $Quiet, [string] $Scope)
     {
         # create a proxy for write-host
         $metaData = New-Object System.Management.Automation.CommandMetaData (Get-Command 'Microsoft.PowerShell.Utility\Write-Host')
         $proxy = [System.Management.Automation.ProxyCommand]::create($metaData)
 
         # change its behavior
         $content = if($quiet)
                    {
                       # in quiet mode, whack the entire function body, simply pass input directly to the pipeline
                       $proxy -replace '(?s)\bbegin\b.+', '$Object'
                    }
                    else
                    {
                       # in noisy mode, pass input to the pipeline, but allow real write-host to process as well
                       $proxy -replace '($steppablePipeline.Process)', '$Object; $1'
                    }  
 
         # load our version into the specified scope
         Invoke-Expression "function ${scope}:Write-Host { $content }"
     }
 
     Cleanup
 
     # if we are running at the end of a pipeline, need to immediately inject our version
     #    into global scope, so that everybody else in the pipeline uses it.
     #    This works great, but dangerous if we don't clean up properly.
     if($pscmdlet.ParameterSetName -eq 'FromPipeline')
     {
        ReplaceWriteHost -Quiet:$quiet -Scope 'global'
     }
   }
 
   process
   {
      # if a scriptblock was passed to us, then we can declare
      #   our version as local scope and let the runtime take it out
      #   of scope for us.  Much safer, but it won't work in the pipeline scenario.
      #   The scriptblock will inherit our version automatically as it's in a child scope.
      if($pscmdlet.ParameterSetName -eq 'FromScriptBlock')
      {
        . ReplaceWriteHost -Quiet:$quiet -Scope 'local'
        & $scriptblock
      }
      else
      {
         # in pipeline scenario, just pass input along
         $InputObject
      }
   }
 
   end
   {
      Cleanup
   }  
}



# default chocolatey install path
$chocolateyPath = "C:\Chocolatey\chocolateyinstall\chocolatey.ps1"
# attempt to find an existing install path
if ($env:ChocolateyInstall)
{
    $chocolateyPath = "$env:ChocolateyInstall\chocolateyinstall\chocolatey.ps1"
}
