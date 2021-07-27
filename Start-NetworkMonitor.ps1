#Requires -RunAsAdministrator

# had issues with conversions in native powershell
# using this for now as a temporary hack
# because PowerShell casting is like Convert.ToUint16
# which is stricter than C# cast
# and bytes needed to be read in as "Int16/Int32" from memory stream
Add-Type -TypeDefinition @'
using System;
public static class Casting
{
    public static UInt16 CastInt16ToUInt16(Int16 input)
    {
        UInt16 result = (UInt16)input;
        return result;
    }
    public static UInt32 CastInt32ToUInt32(Int32 input)
    {
        UInt32 result = (UInt32)input;
        return result;
    }
}
'@

[System.Net.Sockets.Socket]$global:mainSocket = $null
[Byte[]]$global:byteData = New-Object Byte[] 4096
[bool]$global:bContinueCapturing = $true
$global:PSHostUI = $Host.UI

# This Function created as global cause PowerShell.exe won't let me use
# a runtime generated type in a PowerShell class method 
# PowerShell ISE allows it though
Function global:Get-UInt16
{
	param($value)
	return [Casting]::CastInt16ToUInt16($value)
}

Function global:Get-UInt32
{
	param($value)
    return [Casting]::CastInt32ToUInt32($value)
}

Function global:Format-Bytes
{
	param([Byte[]]$bytes,[Int]$Width = 20,[Int]$MaxBytes = 0)
    if ($MaxBytes -eq 0)
    {
        $MaxBytes = $bytes.Length
    }
    $stringBuilder = New-Object System.Text.StringBuilder

    For ($x = 0; $x -lt $MaxBytes; $x+=$Width )
    {
        for ($y = $x; $y -lt $x+$Width -and $y -lt $MaxBytes;$y++)
        {
            [void]$stringBuilder.Append([String]::Format("{0:X2} ",$bytes[$y]))
        }

        if ($y -lt $x+$Width)
        {
            for ($y = $y; $y -lt $x+$Width;$y++)
            {
                [void]$stringBuilder.Append("   ")
            }
        }
        [void]$stringBuilder.Append("| ")
        for ($y = $x; $y -lt $x+$Width -and $y -lt $MaxBytes;$y++)
        {
            if ($bytes[$y] -lt 32)
            {
                [void]$stringBuilder.Append(".")
            }
            else
            {
                [void]$stringBuilder.Append([Char]$bytes[$y])
            }
        }

        [void]$stringBuilder.AppendLine()
    }

    return $stringBuilder.ToString()
}

$global:ClassDefinition = @'
class TCPHeader
{
    # TCP header fields
    [UInt16]$usSourcePort                  
    [UInt16]$usDestinationPort             
    [UInt32]$uiSequenceNumber=555         
    [UInt32]$uiAcknowledgementNumber=555   
    [UInt16]$usDataOffsetAndFlags=555     
    [UInt16]$usWindow=555                 
    [Int16]$sChecksum=555                
    [UInt16]$usUrgentPointer               
    # end of TCP header fields

    [Byte]$byHeaderLength                        
    [UInt16]$usMessageLength              
    [Byte[]]$byTCPData
        
    TCPHeader([Byte[]]$byBuffer, [Int]$nReceived)
    {
        try
        {
            $this.byTCPData = New-Object Byte[] 4096 
            $memoryStream = New-Object System.IO.MemoryStream($byBuffer, 0, $nReceived)
            $binaryReader = New-Object System.IO.BinaryReader($memoryStream)
            
		    $value =  [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usSourcePort = global:Get-UInt16 -Value $value
			$value =  [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usDestinationPort = global:Get-UInt16 -value $value
			$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt32())
            $this.uiSequenceNumber = global:Get-UInt32 -value $value
			$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt32())
            $this.uiAcknowledgementNumber = global:Get-UInt32 -value $value
            $value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
			$this.usDataOffsetAndFlags = global:Get-UInt16 -value $value
            $value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
			$this.usWindow = global:Get-UInt16 -value $value
            $this.sChecksum = [Int16][System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
			$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usUrgentPointer = global:Get-UInt16 -value $value

            # calculate the header length
            $this.byHeaderLength = [Byte]($this.usDataOffsetAndFlags -shr 12)
            $this.byHeaderLength *= 4

            # Message length = Total length of the TCP packet - Header length
            $this.usMessageLength = $nReceived - $this.byHeaderLength

            # Copy the TCP data into the data buffer
            [System.Array]::Copy($byBuffer, $this.byeaderLength, $this.byTCPData, 0, $nReceived - $this.byHeaderLength)
        }
        catch 
        {
            $errMsg = $_
            $global:PSHostUI.WRiteLine("Error reading TCP header $errMsg")
        }
    }

    [String]GetSourcePort()
    {
            return $this.usSourcePort.ToString()
    }

    [String]GetDestinationPort()
    {
        return $this.usDestinationPort.ToString()
    }

    [String]GetSequenceNumber()
    {
        return $this.uiSequenceNumber.ToString()
    }

    [String]GetAcknowledgementNumber()
    {   
        # If the ACK flag is set then only we have a valid value in
        # the acknowlegement field, so check for it beore returning 
        # anything
        if (($this.usDataOffsetAndFlags -band 0x10) -ne 0)
        {
            return $this.uiAcknowledgementNumber.ToString()
        }
        else
        {
            return ""
        }
    }

    [String]GetHeaderLength()
    {
        return $this.usHeaderLength.ToString()
    }

    [String]GetWindowSize()
    {
        return $this.usWindow.ToString()
    }

    [String]GetUrgentPointer()
    {   
        # If the URG flag is set then only we have a valid value in
        # the urgent pointer field, so check for it beore returning 
        # anything
        if (($this.usDataOffsetAndFlags -band 0x20) -ne 0)
        {
            return $this.usUrgentPointer.ToString()
        }
        else
        {
            return ""
        }
    }

    [String]GetMessageLength()
    {
        return $this.usMessageLength.ToString()
    }
    
    [String]GetFlags()
    {
        # The last six bits of the data offset and flags contain the
        # control bits

        # First we extract the flags
        $nFlags = $this.usDataOffsetAndFlags -band 0x3F;
 
        $strFlags = [String]::Format("0x{0:x2} (", $nFlags)

        # Now we start looking whether individual bits are set or not
        if (($nFlags -band 0x01) -ne 0)
        {
            $strFlags += "FIN, "
        }
        if (($nFlags -band 0x02) -ne 0)
        {
            $strFlags += "SYN, "
        }
        if (($nFlags -band 0x04) -ne 0)
        {
            $strFlags += "RST, "
        }
        if (($nFlags -band 0x08) -ne 0)
        {
            $strFlags += "PSH, "
        }
        if (($nFlags -band 0x10) -ne 0)
        {
            $strFlags += "ACK, "
        }
        if (($nFlags -band 0x20) -ne 0)
        {
            $strFlags += "URG"
        }
        $strFlags += ")"

        if ($strFlags.Contains("()"))
        {
            $strFlags = $strFlags.Remove($strFlags.Length - 3)
        }
        elseif ($strFlags.Contains(", )"))
        {
            $strFlags = $strFlags.Remove($strFlags.Length - 3, 2)
        }

        return $strFlags
    }

    [String]GetChecksum()
    {
        return [String]::Format("0x{0:x2}", $this.sChecksum)
    }

    [Byte[]]GetData()
    {
        return $this.byTCPData
    }


}

class IPHeader
{
        # IP Header fields
        [Byte]$byVersionAndHeaderLength
        [Byte]$byDifferentiatedServices
        [UInt16]$usTotalLength
        [UInt16]$usIdentification
        [UInt16]$usFlagsAndOffset
        [Byte]$byTTL
        [Byte]$byProtocol
        [Int16]$sChecksum                    
        [UInt32]$uiSourceIPAddress
        [UInt32]$uiDestinationIPAddress
        # end of IP Header fields
        
        [Byte]$byHeaderLength
        [Byte[]]$byIPData

        IPHeader([Byte[]]$byBuffer, [Int]$nReceived)
        {
            
            try
            {
				$this.byIPData = New-Object System.Byte[] 4096
                $memoryStream = New-Object System.IO.MemoryStream($byBuffer, 0, $nReceived)
                $binaryReader = New-Object System.IO.BinaryReader($memoryStream)
                $this.byVersionAndHeaderLength = $binaryReader.ReadByte()
                $this.byDifferentiatedServices = $binaryReader.ReadByte()
				
				$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
                $this.usTotalLength = global:Get-UInt16 -value $value 
				$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
                $this.usIdentification = global:Get-UInt16 -value $value
			    $value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
                $this.usFlagsAndOffset = global:Get-UInt16 -value $value
                $this.byTTL = $binaryReader.ReadByte()
                $this.byProtocol = $binaryReader.ReadByte()
                $this.sChecksum = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
                $this.uiSourceIPAddress = global:Get-UInt32 -value ($binaryReader.ReadInt32())
                $this.uiDestinationIPAddress = global:Get-UInt32 -value ($binaryReader.ReadInt32())

                $this.byHeaderLength = $this.byVersionAndHeaderLength
                
                #The last four bits of the version and header length field contain the
                # header length, we perform some simple binary airthmatic operations to
                #extract them
                $this.byHeaderLength = $this.byHeaderLength -shl 4
                $this.byHeaderLength = $this.byHeaderLength -shr 4
                # Multiply by four to get the exact header length
                $this.byHeaderLength *= 4
                
                [System.Array]::Copy($byBuffer, 
                            $this.byHeaderLength,  # start copying from the end of the header
                            $this.byIPData, 0, 
                            $this.usTotalLength - $this.byHeaderLength)
            }
            catch 
            {
                $ErrorMsg = $_
                $global:PSHostUI.WRiteLine("Error parsing IP header $ErrorMsg")
            }
        }

        [String]GetVersion()
        {
            if (($this.byVersionAndHeaderLength -shr 4) -eq 4)
            {
                return "IP v4"
            }
            elseif ((byVersionAndHeaderLength -shr 4) -eq 6)
            {
                return "IP v6"
            }
            else
            {
                return "Unknown"
            }
            
        }

        [String]GetHeaderLength()
        {
            return $this.byHeaderLength.ToString()                
        }

        [UInt16]GetMessageLength()
        {
            return $this.usTotalLength - $this.byHeaderLength
        }

        [String]GetDifferentiatedServices()
        {
            return [String]::Format("0x{0:x2} ({1})", $this.byDifferentiatedServices,$this.byDifferentiatedServices)
            
        }

        [String]GetFlags()
        {
            [Int]$nFlags = $this.usFlagsAndOffset -shr 13
            if ($nFlags -eq 2)
            {
                return "Don't fragment"
            }
            elseif ($nFlags -eq 1)
            {
                return "More fragments to come"
            }
            else
            {
                return $nFlags.ToString()
            }
        }

        [String]GetFragmentationOffset()
        {
            [Int]$nOffset = $this.usFlagsAndOffset -shl 3
            $nOffset = $nOffset -shr 3
            return $nOffset.ToString()
        }

        [String]GetTTL()
        {
            return $this.byTTL.ToString()
        }

        [String]GetProtocolType()
        {
            switch ($this.byProtocol)
            {
                6 { return "TCP" }
                17 { return "UDP" }
            }
            return "Unknown"
        }

        [String]GetChecksum()
        {
            return [String]::Format("0x{0:x2}", $this.sChecksum)
        }

        [System.Net.IPAddress]GetSourceAddress()
        {
            return New-Object System.Net.IPAddress($this.uiSourceIPAddress)
        }

        [System.Net.IPAddress]GetDestinationAddress()
        {
            return New-Object System.Net.IPAddress($this.uiDestinationIPAddress)
        }

        [String]GetTotalLength()
        {
            return $this.usTotalLength.ToString()
        }

        [String]GetIdentification()
        {
            return $this.usIdentification.ToString()
        }

        [Byte[]]GetData()
        {
            return $this.byIPData
        }
    }

class UDPHeader
{
    # UDP header fields
    [UInt16]$usSourcePort               
    [UInt16]$usDestinationPort     
    [UInt16]$usLength                
    [Int16]$sChecksum               
                                                             
    # End of UDP header fields
    [Byte[]]$byUDPData
        
    UDPHeader([Byte[]]$byBuffer, [Int]$nReceived)
    {
        try
        {
            $this.byUDPData = New-Object System.Byte[] 4096
            $memoryStream = New-Object System.IO.MemoryStream($byBuffer, 0, $nReceived)
            $binaryReader = New-Object System.IO.BinaryReader($memoryStream)
           
		    $value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usSourcePort = global:Get-UInt16 -value $value
			$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usDestinationPort = global:Get-UInt16 -value $value 
			$value = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usLength = global:Get-UInt16 -value $value 
            $this.sChecksum = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())          

            # The UDP header is 8 bytes so we start copying after it
            [System.Array]::Copy($byBuffer,8,$this.byUDPData,0,$nReceived - 8)
        }
        catch
        {
            $ErrorMsg = $_
            $global:PSHostUI.WRiteLine("Error parsing UDP header $ErrorMsg")
        }
    }

    [String]GetSourcePort()
    {
            return $this.usSourcePort.ToString()
    }

    [String]GetDestinationPort()
    {
        return $this.usDestinationPort.ToString()
    }

    [String]GetLength()
    {
        return $this.usLength.ToString()
    }

    [String]GetChecksum()
    {
        return [String]::Format("0x{0:x2}", $this.sChecksum)
    }

    [Byte[]]GetData()
    {
        return $this.byUDPData
    }
}

class DNSHeader
{
    # dns header fields
    [Int16]$usIdentification
    [Int16]$usFlags
    [Int16]$usTotalQuestions   
    [Int16]$usTotalAnswerRRs
    [Int16]$usTotalAuthorityRRs
    [Int16]$usTotalAdditionalRRs
    # end DNS header fields

    DNSHeader([Byte[]]$byBuffer, [Int]$nReceived)
    {
        try
        {
            $memoryStream = New-Object System.IO.MemoryStream($byBuffer, 0, $nReceived)
            $binaryReader = New-Object System.IO.BinaryReader($memoryStream)    
            $this.usIdentification = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usFlags = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usTotalQuestions = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usTotalAnswerRRs = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usTotalAuthorityRRs = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
            $this.usTotalAdditionalRRs = [System.Net.IPAddress]::NetworkToHostOrder($binaryReader.ReadInt16())
        }
        catch
        {
            $ErrorMsg = $_
            $global:PSHostUI.WRiteLine("Error parsing DNS header $ErrorMsg")
        }
    }

    [String]GetIdentification()
    {
        return [String]::Format("0x{0:x2}", $this.usIdentification)
    }

    [String]GetFlags()
    {
        return [String]::Format("0x{0:x2}", $this.usFlags)
    }

    [String]GetTotalQuestions()
    {
        return $this.usTotalQuestions.ToString()
    }

    [String]GetTotalAnswerRRs()
    {
        return $this.usTotalAnswerRRs.ToString()
            
    }

    [String]GetTotalAuthorityRRs()
    {
        return $this.usTotalAuthorityRRs.ToString()
    }

    [String]GetTotalAdditionalRRs()
    {
        return $this.usTotalAdditionalRRs.ToString()
    }
}
'@

Invoke-Expression $global:ClassDefinition

function New-ScriptBlockCallback {
    param(
        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$Callback
    )
<#
    .SYNOPSIS
        Allows running ScriptBlocks via .NET async callbacks.
 
    .DESCRIPTION
        Allows running ScriptBlocks via .NET async callbacks. Internally this is
        managed by converting .NET async callbacks into .NET events. This enables
        PowerShell 2.0+ to run ScriptBlocks indirectly through Register-ObjectEvent.        
 
    .PARAMETER Callback
        Specify a ScriptBlock to be executed in response to the callback.
        Because the ScriptBlock is executed by the eventing subsystem, it only has
        access to global scope. Any additional arguments to this function will be
        passed as event MessageData.
       
    .EXAMPLE
        You wish to run a scriptblock in reponse to a callback. Here is the .NET
        method signature:
       
        void Bar(AsyncCallback handler, int blah)
       
        ps> [foo]::bar((New-ScriptBlockCallback { ... }), 42)                        
 
    .OUTPUTS
        A System.AsyncCallback delegate.
#>
    # is this type already defined?    
    if (-not ("CallbackEventBridge" -as [type])) {
        Add-Type @"
using System;
           
public sealed class CallbackEventBridge
{
public event AsyncCallback CallbackComplete = delegate { };
 
private CallbackEventBridge() {}
 
private void CallbackInternal(IAsyncResult result)
{
    CallbackComplete(result);
}
 
public AsyncCallback Callback
{
    get { return new AsyncCallback(CallbackInternal); }
}
 
public static CallbackEventBridge Create()
{
    return new CallbackEventBridge();
}
}
"@
    }
    $bridge = [callbackeventbridge]::create()
    Register-ObjectEvent -Input $bridge -EventName callbackcomplete -action $callback -messagedata $args > $null
    $bridge.callback
}


Function global:Parse-Data
{
    param([Byte[]]$byteData,[Int]$nReceived)
    try
    {
		Invoke-Expression $global:ClassDefinition

		$ipHeader = New-Object IPHeader($byteData, $nReceived)
		
        $global:PSHostUI.WriteLine("$($ipHeader.GetVersion()) SOURCE: $($ipHeader.GetSourceAddress()) DEST: $($ipHeader.GetDestinationAddress()) TTL=$($ipHeader.GetTTL()) Checksum=$($ipHeader.GetChecksum()) Flags=$($ipHeader.GetFlags())")

        switch ($ipHeader.GetProtocolType())
        {
            "TCP" 
            {
                $global:PSHostUI.WriteLine("Getting TCP Header")
                $tcpHeader = New-Object TCPHeader($ipHeader.GetData(),$ipHeader.GetMessageLength())
                $global:PSHostUI.WriteLine("SOURCE TCP PORT: $($tcpHeader.GetSourcePort()) DEST TCP PORT: $($tcpHeader.GetDestinationPort())")
            
                if ($tcpHeader.GetDestinationPort() -eq 53 -or $tcpHeader.GetSourcePort() -eq 53)
                {
                    $dnsHeader = New-Object DNSHeader($tcpHeader.GetData(),$tcpHeader.GetMessageLength())
                    global:Parse-DnsHeader $dnsHeader
                }
            } 
            "UDP" 
            {
                $udpHeader = New-Object UDPHeader($ipHeader.GetData(),$ipHeader.GetMessageLength())
                $global:PSHostUI.WriteLine("SOURCE UDP PORT: $($udpHeader.GetSourcePort()) DEST UDP PORT: $($udpHeader.GetDestinationPort())")
            
                if ($udpHeader.GetDestinationPort() -eq 53 -or $udpHeader.GetSourcePort() -eq 53)
                {
                    $dnsHeader = New-Object DNSHeader($udpHeader.GetData(),$udpHeader.GetLength() - 8)
                    global:Parse-DnsHeader $dnsHeader
                }
            } 
        }

        $global:PSHostUI.WriteLine("RAW BYTES")
        $formattedBytes = global:Format-Bytes -bytes $byteData -Width 40 -MaxBytes $nReceived
        $global:PSHostUI.WriteLine($formattedBytes)

    }
    catch
    {
        $errMsg = $_
        $global:PSHostUI.WRiteLine("Parse error: $errMsg") 
    }
}

Function global:Parse-DnsHeader
{
    param([DNSHeader]$dnsHeader)
    $global:PSHostUI.WriteLine("*** DNS DATA *** ")
    $global:PSHostUI.WriteLine("Total Questions : $($dnsHeader.GetTotalQuestions)")
    $global:PSHostUI.WriteLine("Total Answer RRs: $($dnsHeader.GetTotalAnswerRRs)")
    $global:PSHostUI.WriteLine("Additional RRs  : $($dnsHeader.GetTotalAdditionalRRs)")
    $global:PSHostUI.WriteLine("Identification  : $($dnsHeader.GetIdentification())")
    $global:PSHostUI.WRiteLine("DNS Flags       : $($dnsHeader.GetFlags())")
}


$global:callback = New-ScriptBlockCallback {
        param($ar)
        try
        {
            $nReceived = $global:mainSocket.EndReceive($ar)
            $global:PSHostUI.WriteLine("$nReceived Bytes Transferred")
            Parse-Data -byteData $global:byteData -nReceived $nReceived
        }
        catch
        {
            $errMsg = $_
            $global:PSHostUI.WRiteLine("Parse error: $errMsg") 
        }
        if ($global:bContinueCapturing)
        {
            $global:byteData = New-Object Byte[] 4096
            $global:mainSocket.BeginReceive( `
                $global:byteData, `
                0, `
                $global:byteData.Length, `
                "None", `
                $global:callback, 
                $null)
        }
    }
Function Start-Capture
{
    param([System.Net.IPAddress]$BindAddress)
    $global:mainSocket = New-Object System.Net.Sockets.Socket("InterNetwork","Raw","IP")
    $global:mainSocket.Bind((New-Object System.Net.IPEndPoint($BindAddress, 0)))
    $global:mainSocket.SetSocketOption("IP","HeaderIncluded",$true)
    [Byte[]]$byTrue =  @(1, 0, 0, 0) # capture incoming
    [Byte[]]$byOut =   @(1, 0, 0, 0) # capturing outgoing

    # Equivalent to SIO_RCVALL constant of Winsock 2
    $global:mainSocket.IOControl(0x98000001, $byTrue, $byOut)
    
    return $global:mainSocket.BeginReceive( `
        $global:byteData, `
        0, `
        $global:byteData.Length, `
        "None", `
        $global:callback, 
        $null)
}

$adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -ne $null } | Sort-Object -Property Description


Write-Host "PowerShell Network Monitor"
For ($i=0;$i -lt $adapters.Length;$i++)
{
    Write-Host "[$i] $($adapters[$i].Description) ($($adapters[$i].IPAddress[0]))" 
}

$addressToMonitor = Read-Host -Prompt "Please select adapter to monitor"

$ayncState = Start-Capture -BindAddress $adapters[$addressToMonitor ].IPAddress[0]

