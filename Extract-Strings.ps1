<#
.SYNOPSIS
Extracts strings from a file.

.DESCRIPTION
Extracts western printable character strings from a binary file, including ASCII strings and UTF16 strings of a minimum length.

.PARAMETER Path
Specifies the path to the file from which strings will be extracted.

.PARAMETER MinStringLength
Specifies the minimum length of strings to be extracted. The default value is 5.

.PARAMETER HideAsciiStrings
Specifies whether to hide ASCII strings. By default, ASCII strings are shown.

.PARAMETER HideUnicodeStrings
Specifies whether to hide Unicode strings. By default, Unicode strings are shown.

.EXAMPLE
Extract-Strings -Path "C:\Files\sample.exe"
Extracts strings from the file "c:\Files\Sample.exe".

Extract-Strings -Path "C:\Files\sample.exe" -HideUnicodeStrings

.INPUTS
None.

.OUTPUTS
Extracted strings are written to the pipeline.

.NOTES
Version: 1.0
Author: chentiangemalc

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType 'Leaf'})]
    [string]$Path,
    [int]$MinStringLength = 5,
    [switch]$HideAsciiStrings,
    [switch]$HideUnicodeStrings
)

$bytes = [System.IO.File]::ReadAllBytes($Path)
$currentASCIIstring = [System.Text.StringBuilder]::new()
$currentUNICODEstring = [System.Text.StringBuilder]::new()
    
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($i + 1 -lt $bytes.Length) {
        if (($bytes[$i] -ge 0x20 -and $bytes[$i] -le 0x7E -or $bytes[$i] -eq 0x0D -or $bytes[$i] -eq 0x0A) -and $bytes[$i + 1] -eq 0x00) {
            [void]$currentUNICODEstring.Append([char]$bytes[$i])
        }
        elseif ($bytes[$i] -eq 0x00 -and $bytes[$i + 1] -eq 0x00) {
            if ($currentUNICODEstring.Length -ge $minStringLength) {
                if (!$HideUnicodeStrings)
                {
                    $currentUNICODEstring.ToString()
                }
            }

            [void]$currentUNICODEstring.Clear()
        }
    }

    if ($bytes[$i] -ge 0x20 -and $bytes[$i] -le 0x7E -or $bytes[$i] -eq 0x0D -or $bytes[$i] -eq 0x0A) {
       [void]$currentASCIIstring.Append([char]$bytes[$i])
    }
    elseif ($bytes[$i] -eq 0) {
        if ($currentASCIIstring.Length -ge $minStringLength) {
            if (!$HideAsciiStrings)
            {
                $currentASCIIstring.ToString()
            }
        }
        [void]$currentASCIIstring.Clear()
    }
    else {
        [void]$currentASCIIstring.Clear()
        [void]$currentUNICODEstring.Clear()
    }
}
