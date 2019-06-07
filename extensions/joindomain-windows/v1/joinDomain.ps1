#
# Optional parameters to this script file.
#

[CmdletBinding()]
param(
    # comma- or semicolon-separated list of Chocolatey packages.
    [string] $DomainName,
    [string] $JoinUser,
    [string] $JoinPassword,
    [string] $OU,
    [int] $PSVersionRequired = 3
)

###################################################################################################
$JoinPasswordSecure = ConvertTo-SecureString $JoinPassword -AsPlainText -Force

$credential = New-Object System.Management.Automation.PSCredential($JoinUser, $JoinPasswordSecure)
if($OU) {
    [Microsoft.PowerShell.Commands.ComputerChangeInfo]$computerChangeInfo = Add-Computer -ComputerName $VmName -DomainName $DomainName -Credential $credential -OUPath $OU -Force -PassThru
} else {
    [Microsoft.PowerShell.Commands.ComputerChangeInfo]$computerChangeInfo = Add-Computer -ComputerName $VmName -DomainName $DomainName -Credential $credential -Force -PassThru
}
if ($computerChangeInfo.HasSucceeded)
{
    Write-Output "Result: Successfully joined the $DomaintoJoin domain"
}
else
{
    Write-Error "Result: Failed to join $env:COMPUTERNAME to $DomaintoJoin domain"
}
