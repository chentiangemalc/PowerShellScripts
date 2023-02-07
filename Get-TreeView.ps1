param (
    [string]$Path = (Get-Location),
    [switch]$ShowFilenames 
)

$dirCount = 0
$fileCount = 0

Function Register-AbsolutePath {
  param($absolute)
  if (Test-Path -PathType Container $absolute) {
    $global:dirCount++
  } else {
    $global:fileCount++
  }
}

Function Get-Summary {
  return "$($global:dirCount) directories, $($global:fileCount) files"
}

Function Walk-Directory {
  param($directory, $prefix = "")
  
  if ($ShowFilenames)
  {
    $filepaths = @(Get-ChildItem -Path $directory | Sort-Object Name | Select-Object -ExpandProperty Name)
  }
  else
  {
    $filepaths = @(Get-ChildItem -Path $directory -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
  }
  for ($i = 0; $i -lt $filepaths.Length; $i++) {
    if ($filepaths[$i][0] -eq ".") {
      continue
    }
    $absolute = Join-Path -Path $directory -ChildPath $filepaths[$i]
    Register-AbsolutePath -absolute $absolute
    if ($i -eq $filepaths.Length - 1) {
      Write-Host "$prefix`└── $($filepaths[$i])"
      if (Test-Path -PathType Container $absolute) {
        Walk-Directory -directory $absolute -prefix "$prefix    "
      }
    } else {
      Write-Host "$prefix`├── $($filepaths[$i])"
      if (Test-Path -PathType Container $absolute) {
       Walk-Directory -directory $absolute -prefix "$prefix`│   "
      }
    }
  }
}

Write-Host $path

Walk-Directory -directory $path
Write-Host ""
Write-Host (Get-Summary)
