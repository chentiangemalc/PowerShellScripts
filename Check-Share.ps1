﻿$code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GetNetShares
{
    #region External Calls
    [DllImport("Netapi32.dll", SetLastError = true)]
    static extern int NetApiBufferFree(IntPtr Buffer);
    [DllImport("Netapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int NetShareEnum(
         StringBuilder ServerName,
         int level,
         ref IntPtr bufPtr,
         uint prefmaxlen,
         ref int entriesread,
         ref int totalentries,
         ref int resume_handle
         );
    #endregion
    #region External Structures
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHARE_INFO_1
    {
        public string shi1_netname;
        public uint shi1_type;
        public string shi1_remark;
        public SHARE_INFO_1(string sharename, uint sharetype, string remark)
        {
            this.shi1_netname = sharename;
            this.shi1_type = sharetype;
            this.shi1_remark = remark;
        }
        public override string ToString()
        {
            return shi1_netname;
        }
    }
    #endregion
    const uint MAX_PREFERRED_LENGTH = 0xFFFFFFFF;
    const int NERR_Success = 0;
    private enum NetError : uint
    {
        NERR_Success = 0,
        NERR_BASE = 2100,
        NERR_UnknownDevDir = (NERR_BASE + 16),
        NERR_DuplicateShare = (NERR_BASE + 18),
        NERR_BufTooSmall = (NERR_BASE + 23),
    }
    private enum SHARE_TYPE : uint
    {
        STYPE_DISKTREE = 0,
        STYPE_PRINTQ = 1,
        STYPE_DEVICE = 2,
        STYPE_IPC = 3,
        STYPE_SPECIAL = 0x80000000,
    }
    public static SHARE_INFO_1[] EnumNetShares(string Server)
    {
        List<SHARE_INFO_1> ShareInfos = new List<SHARE_INFO_1>();
        int entriesread = 0;
        int totalentries = 0;
        int resume_handle = 0;
        int nStructSize = Marshal.SizeOf(typeof(SHARE_INFO_1));
        IntPtr bufPtr = IntPtr.Zero;
        StringBuilder server = new StringBuilder(Server);
        int ret = NetShareEnum(server, 1, ref bufPtr, MAX_PREFERRED_LENGTH, ref entriesread, ref totalentries, ref resume_handle);
        if (ret == NERR_Success)
        {
            IntPtr currentPtr = bufPtr;
            for (int i = 0; i < entriesread; i++)
            {
                SHARE_INFO_1 shi1 = (SHARE_INFO_1)Marshal.PtrToStructure(currentPtr, typeof(SHARE_INFO_1));
                ShareInfos.Add(shi1);
                currentPtr += nStructSize;
            }
            NetApiBufferFree(bufPtr);
            return ShareInfos.ToArray();
        }
        else
        {
            ShareInfos.Add(new SHARE_INFO_1("ERROR=" + ret.ToString(), 10, string.Empty));
            return ShareInfos.ToArray();
        }
    }
}
'@

Add-Type -TypeDefinition $code

$hostName = "localhost"
$targetShare = "f$"
$Timeout = 1000   # increase for high latency networks
$remotePort = 445 # or port 139 if needed
$IP = Resolve-DnsName -Name $hostName -Type A
$tcpClient = New-Object System.Net.Sockets.TcpClient
$portOpened = $tcpClient.ConnectAsync($IP[0].IPAddress, $remotePort).Wait($Timeout)
if ($portOpened)
{
    $shareExists = [GetNetShares]::EnumNetShares($hostName) | Where-Object { $_.shi1_netname -eq $targetShare }

    if ($shareExists -ne $null)
    {
        Write-Host "Target share exists!"               
    }
    else
    {
        Write-Host "Target Share not found!"
    }
}
else
{
    Write-Host "Not listening on port"
}
