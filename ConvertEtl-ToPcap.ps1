[CmdletBinding()]
param(
[Parameter(Position=0)]
[ValidateScript({
    if( -Not ($_ | Test-Path) ){
        throw "File or folder $_ does not exist"
    }

    if($_.Extension -ne ".etl"){
        throw "Source file must be .etl file"
    }
    return $true
})]
[System.IO.FileInfo]$Path,

[Parameter(Position=1)]
[ValidateScript({
    if( -Not ($path.DirectoryName | Test-Path) ){
        throw "File or folder does not exist"
    }

    if($_.Extension -ne ".pcap") {
        throw "Estination file must be .pcap file"
    }
    return $true
})]
[System.IO.FileInfo]$Destination,

[Parameter(Position=2)]
[Uint32]$MaxPacketSizeBytes = 65536)


$csharp_code = @'
using System;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace chentiangemalc
{
    public static class NetworkRoutines
    {
        public static void ConvertEtlToPcap(string source, string destination, UInt32 maxPacketSize)
        {
            var networkTrace = new Guid("{00000001-0000-0000-0000-000000000000}");
            using (BinaryWriter writer = new BinaryWriter(File.Open(destination, FileMode.Create)))
            {

                UInt32 magic_number = 0xa1b2c3d4;
                UInt16 version_major = 2;
                UInt16 version_minor = 4;
                Int32 thiszone = 0;
                UInt32 sigfigs = 0;
                UInt32 snaplen = maxPacketSize;
                UInt32 network = 1; // LINKTYPE_ETHERNET

                writer.Write(magic_number);
                writer.Write(version_major);
                writer.Write(version_minor);
                writer.Write(thiszone);
                writer.Write(sigfigs);
                writer.Write(snaplen);
                writer.Write(network);

                using (var reader = new EventLogReader(source, PathType.FilePath))
                {
                    EventRecord record;
                    while ((record = reader.ReadEvent()) != null)
                    {
                        using (record)
                        {
                            if (record.ActivityId == networkTrace)
                            {
                                DateTime timeCreated = (DateTime)record.TimeCreated;

                                UInt32 ts_sec = (UInt32)((timeCreated.Subtract(new DateTime(1970, 1, 1))).TotalSeconds);
                                UInt32 ts_usec = (UInt32)(((timeCreated.Subtract(new DateTime(1970, 1, 1))).TotalMilliseconds) - ((UInt32)((timeCreated.Subtract(new DateTime(1970, 1, 1))).TotalSeconds * 1000))) * 1000;
                                UInt32 incl_len = (UInt32)record.Properties[2].Value;
                                if (incl_len > maxPacketSize)
                                {
                                    throw new System.InvalidOperationException(String.Format("Packet size of {0} exceeded max packet size {1}", incl_len, maxPacketSize));
                                }
                                UInt32 orig_len = incl_len;

                                writer.Write(ts_sec);
                                writer.Write(ts_usec);
                                writer.Write(incl_len);
                                writer.Write(orig_len);
                                writer.Write((byte[])record.Properties[3].Value);

                            }
                        }
                    }
                }

            }

        }
    }
}
'@

Add-Type -Type $csharp_code

[chentiangemalc.NetworkRoutines]::ConvertEtlToPcap($PAth.FullName,$Destination.FullName,$MaxPacketSizeBytes)
