<#
.SYNOPSIS

    Displays the password of an Access 2003-2007 (MDB) file

.DESCRIPTION

    Decrypts Access Database password.

.PARAMETER Path

    The access database file of which to display the password.
        
.INPUTS

  None
  
.OUTPUTS

  None
  
.NOTES

  Version:        1.0

  Author:         chentiangemalc

  Creation Date:  6 Sep 2022

  Purpose/Change: Initial script development

  
.EXAMPLE

  .\Get-MdbPassword.ps1 -Path c:\test\test.mdb

#>

[CmdletBinding()]Param(
[Parameter(Mandatory=$true)]
[ValidateScript({
    if( -Not ($_ | Test-Path) ){
        throw "File or folder does not exist"
    }

    if(-Not ($_ | Test-Path -PathType Leaf) ){
        throw "The Path argument must be a file. Folder paths are not allowed."
    }
    return $true
})]
[string]$Path)

[Byte[]]$global:decoderKey = @( 
   0xBA,0x6A,0xEC,0x37,0x61,0xD5,0x9C,0xFA,0xFA,
   0xCF,0x28,0xE6,0x2F,0x27,0x8A,0x60,0x68,0x05,
   0x7B,0x36,0xC9,0xE3,0xDF,0xB1,0x4B,0x65,0x13,
   0x43,0xF3,0x3E,0xB1,0x33,0x08,0xF0,0x79,0x5B,
   0xAE,0x24,0x7C,0x2A,0x00,0x00,0x00,0x00)

Function Decode-Data([Byte[]]$data,[System.Text.Encoding]$Encoding)
{
    switch($Encoding.EncodingName)
    {
        "Unicode" { $decodeSize = 40 }
        default: { throw "Unknown encoding type" }
    }

    $dataPosition = 0
    [Byte]$key1 = $global:decoderKey[36] -bxor $data[36]
    [Byte]$key3 = $global:decoderKey[37] -bxor $data[37]
    [byte]$key4 = 0
    
    for ($counter = 0; $counter -lt $decodeSize;$counter++)
    {
        $key4 = $data[$counter] -bxor $global:decoderKey[$counter]
        $data[$counter]=$key4
        if (!($counter % 4)) { $data[$counter] = $key1 -bxor $key4 }
        if (($counter % 4) -eq 1) { $data[$counter] = $data[$counter] -bxor $key3 }

    }

    $outString = $encoding.GetString($data)
    $outString = $outString.Substring(0,$outString.IndexOf([Char]0))
    $outString 
}

$stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$reader = New-Object System.IO.BinaryReader($stream)
$chunk = $reader.ReadBytes(128)
if ($chunk[4] -eq 0x53 -and
    $chunk[5] -eq 0x74 -and
    $chunk[6] -eq 0x61 -and
    $chunk[13] -eq 0x4A -and
    $chunk[14] -eq 0x65)
{
    [void]$reader.BaseStream.Seek(66, [System.IO.SeekOrigin]::Begin)
    $chunk = $reader.ReadBytes(128)
    if ($chunk[90] -eq 0x34 -and
        $chunk[91] -eq 0x2E -and
        $chunk[92] -eq 0x30)
    {
        Decode-Data -Data $chunk -Encoding ([System.Text.Encoding]::Unicode)
        
    }
    else
    {
        # note: Expect ASCII encoding based file to use decode size of 85 
        # but don't have any example file to test with at the moment
        throw "Unknown Encoding"
    }
}
else
{
    throw "Unexpected data!"
}

$reader.Close()
$stream.Close()