$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xSCDPMHelper.psm1 -Verbose:$false -ErrorAction Stop

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $SCDPMServer,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SetupCredential
    )

    $Ensure = "Absent"

    $DPMFolder = Join-Path -Path (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft Data Protection Manager\Setup" -Name "InstallPath").InstallPath -ChildPath "ActiveOwner"
    if($Files = Get-ChildItem -Path "$DPMFolder" -Filter "*.")
    {
        foreach($File in $Files)
        {
            $ActiveOwner = Get-Content -Path (Join-Path -Path $DPMFolder -ChildPath $File) -Encoding Unicode
            if($ActiveOwner.Substring(0,$SCDPMServer.Length) -eq $SCDPMServer)
            {
                $Ensure = Invoke-Command -ComputerName $SCDPMServer -Credential $SetupCredential -Authentication Credssp {
                    $ComputerName = $args[0]
                    $Ensure = "Absent"
                    $DPMServer = Connect-DPMServer -DPMServerName $env:COMPUTERNAME
                    $DPMAgents = $DPMServer.GetProductionServers()
                    foreach($DPMAgent in $DPMAgents)
                    {
                        if(($DPMAgent.ServerName -eq $ComputerName) -and ($DPMAgent.ServerProtectionState -ne "Deleted"))
                        {
                            $Ensure = "Present"
                        }
                    }
                    $Ensure
                } -ArgumentList @($env:COMPUTERNAME)
            }
        }
    }

    if($Ensure -eq "Absent")
    {
        $SCDPMServer = ""
    }

    $returnValue = @{
        Ensure = $Ensure
        SCDPMServer = $SCDPMServer
    }

    $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $SCDPMServer,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SetupCredential
    )

    if($Ensure -eq "Present")
    {
        Import-Module $PSScriptRoot\..\..\xPDT.psm1

        $Path = Join-Path -Path (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft Data Protection Manager\Setup" -Name "InstallPath").InstallPath -ChildPath "bin\SetDpmServer.exe"
        $Path = Resolve-Path $Path
        $Arguments = "-Add -dpmServerName $SCDPMServer"

        Write-Verbose "Path: $Path"
        Write-Verbose "Arguments: $Arguments"

        $Process = StartWin32Process -Path $Path -Arguments $Arguments -Credential $SetupCredential
        Write-Verbose $Process
        WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments -Credential $SetupCredential
    }

    $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
    $ComputerName = "$($env:COMPUTERNAME).$($ComputerSystem.Domain)"

    Invoke-Command -ComputerName $SCDPMServer -Credential $SetupCredential -Authentication Credssp {
        $Ensure = $args[0]
        $ComputerName = $args[1]
        $SetupCredential = $args[2]
        $DPMServer = Connect-DPMServer -DPMServerName $env:COMPUTERNAME
        if($DPMServer)
        {
            switch($Ensure)
            {
                "Present"
                {
                    $DPMServer.AttachProductionServer($ComputerName,$SetupCredential.GetNetworkCredential().UserName,$SetupCredential.Password,$SetupCredential.GetNetworkCredential().Domain)
                }
                "Absent"
                {
                    $DPMServer.RemoveProductionServer($ComputerName)
                }
            }
        }
    } -ArgumentList @($Ensure,$ComputerName,$SetupCredential)

    $i = 0
    while (!(Test-TargetResource @PSBoundParameters) -and ($i -le 60))
    {
        $i++
        Start-Sleep 1
    }

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $SCDPMServer,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SetupCredential
    )

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)
    
    $result
}


Export-ModuleMember -Function *-TargetResource
