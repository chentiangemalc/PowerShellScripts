<#

.SYNOPSIS

  Extracts all DNS Resource Records from Specified Windows DNS Server

.DESCRIPTION

  Formats data suitable for export to CSV.

.PARAMETER DNSServer

  Specifies DNS server to query.

.INPUTS

  None.

.OUTPUTS

  Data sent to pipeline.

.NOTES

  Version:        1.0

  Author:         Malcolm McCaffery

  Creation Date:  17/10/2018

  Purpose/Change: Initial script development


.EXAMPLE

    Get-AllDnsResourceRecords -DnsServer 8.8.8.8
    Get-AllDnsResourceRecords -DnsServer 8.8.8.8 | Export-Csv -NoTypeInformation -Path c:\support\DnsRecords.csv
#> 
[CmdletBinding()]
param(
[Parameter(Position=0)]
[String]$DNSServer)

$Zones = @(Get-DnsServerZone -ComputerName $DNSServer)
$Data = @() 
ForEach ($Zone in $Zones) {
	($Zone | Get-DnsServerResourceRecord -ComputerName $DNSServer) | `
        Select-Object -Property `
            @{Label="Zone Name";expression={( $Zone.ZoneName )}},`
            DistinguishedName,`
            HostName,`
            RecordClass,`
            RecordType,`
            Timestamp,`
            TimeToLive,`
            @{label="Data";expression={
                $r = $_.RecordData
                switch ($_.RecordType)
                {
                    "A" { $r.IPv4Address.IPAddressToString }
                    "NS" { $r.NameServer }
                    "SOA" { 
                        "ExpireLimit=$($r.ExpireLimit);"+
                        "MinimumTimeToLive=$($r.MinimumTimeToLive);"+
                        "PrimaryServer=$($r.PrimaryServer);"+
                        "RefreshInterval=$($r.RefreshInterval);"+
                        "ResponsiblePerson=$($r.ResponsiblePerson);"+
                        "RetryDelay=$($r.RetryDelay);"+
                        "SerialNumber=$($r.SerialNumber)"

                    }
                    "CNAME" {  $r.HostNameAlias }
                    "SRV"{ 
                        "DomainName=$($r.DomainName);"+
                        "Port=$($r.Port);"+
                        "Priority=$($r.Priority);"+
                        "Weight=$($r.Weight)"
                    }
                    "AAAA" { $r.IPv6Address.IPAddressToString }
                    "PTR" { $r.PtrDomainName } 
                    "MX" {
                        "MailExchange=$($r.MailExchange);"+
                        "Prefreence=$($r.Preference)"
                    }
                    "TXT" { $r.DescriptiveText }
                    Default { "Unsupported Record Type" }
                }}
            }
}


