#
# Join Windows to a Domain
#

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $DomainName,
    [Parameter(Mandatory = $true)]
    [string] $JoinUser,
    [Parameter(Mandatory = $true)]
    [string] $JoinPassword,
    [Parameter(Mandatory = $true)]
    [string] $OU,
    [int] $PSVersionRequired = 3
)

Write-Output "Creating credentials..."

###################################################################################################

$JoinPasswordSecure = ConvertTo-SecureString $JoinPassword -AsPlainText -Force

$credential = New-Object System.Management.Automation.PSCredential($JoinUser, $JoinPasswordSecure)

Write-Output "Joining domain..."

if($OU) {
    [Microsoft.PowerShell.Commands.ComputerChangeInfo]$computerChangeInfo = Add-Computer -ComputerName $env:COMPUTERNAME -DomainName $DomainName -Credential $credential -OUPath $OU -Force -PassThru
} else {
    [Microsoft.PowerShell.Commands.ComputerChangeInfo]$computerChangeInfo = Add-Computer -ComputerName $env:COMPUTERNAME -DomainName $DomainName -Credential $credential -Force -PassThru
}
if ($computerChangeInfo.HasSucceeded)
{
    Write-Output "Result: Successfully joined the $DomaintoJoin domain"
}
else
{
    Write-Error "Result: Failed to join $env:COMPUTERNAME to $DomaintoJoin domain"
}
