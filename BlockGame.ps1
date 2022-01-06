clear

# must run in powershell console, not powershell ISE
$height = $Host.UI.RawUI.WindowSize.Height
$width  = $Host.UI.RawUI.WindowSize.Width
$level = 0
$score = 0
$playAreaHeight = 40
$playAreaWidth = 10 
$scoreBoxTop = 5
$scoreBoxLeft = 5
$totalLines = 0
$levelLines = 0
$highScoreFile = "$PSScriptRoot\BlocksHighScore.json"

# scales size of objects across Y axis
$playAreaScaleY = 2
$playAreaTop = 1
$playAreaLeft = ($width - ($playAreaWidth*$playAreaScaleY))/2

# esc character for ansi codes
$esc = [char]27
# ms delay for piece drop
$delay = (10-$level)*30

# default values if height/width not detected
if ($height -eq $null) { $height = 50 }
if ($width -eq $null) { $width = 120 } 

$blocks = @(
    @( 
    @(0,1,0),
    @(1,1,1)),
    @(
    @(2),
    @(2),
    @(2),
    @(2)),
    @(
    @(3,0,0),
    @(3,3,3)),
    @(
    @(0,0,4),
    @(4,4,4)),
    @(
    @(5,5),
    @(5,5)),
    @(
    @(0,6,6),
    @(6,6,0)),
    @(
    @(7,7,0),
    @(0,7,7)
    ))

$playingBoard = New-Object 'int[,]' ($playAreaHeight+1),($playAreaWidth+1)

# draw the board
for ($x=1;$x -lt $height;$x++)
{
    for ($y=1;$y -lt $width;$y++)
    {
    
        if ($x -ge $playAreaTop -and 
            $x -lt $playAreaTop+$playAreaHeight -and 
            $y -ge $playAreaLeft -and
            $y -lt $playAreaLeft+($playAreaWidth*$playAreaScaleY))
        {
            Write-Output "$esc[$($x);$($y)H$esc[0;0;0m "
        }
        else
        {
            Write-Output "$esc[$($x);$($y)H$esc[48;5;57m "
        }
    }
}

for ($x=0;$x -le 4;$x++)
{
    for ($y=0;$y -le 40;$y++)
    {
        if ($x -gt 0 -and $x -le 40 -or $y -gt 0 -and $y -le 4)
        { 
            Write-Output "$esc[$($x+$scoreBoxTop);$($y+$scoreBoxLeft)H$esc[0;93m "
        }
        else
        {
            Write-Output "$esc[$($x+$scoreBoxTop);$($y+$scoreBoxLeft)H$esc[0;96m "
        }
    }
}

$doExit = $false

while (!$doExit)
{

    Write-Output "$esc[$($scoreBoxTop+2);$($scoreBoxLeft+1)H$esc[0;96m LEVEL: $level LINES: $totalLines SCORE: $score"
    # select a random piece
    $pieceNumber = (Get-Random -Minimum 0 -Maximum ($blocks.Count-1))
    $currentPiece = $blocks[$pieceNumber]
    $previousPiece = $currentPiece
    $currentY = $playAreaWidth/2 - $Blocks[0].Count/2

    $previousX = 0
    $previousY = $currentY
    $collision = $false

    # drop selected piece
    for ($currentX = 0;$currentX -le $playAreaHeight-$currentPiece.Count;$currentX++)
    {
        # check for collision
        for ($x = 0;$x -lt $currentPiece.Count;$x++)
        {
            for ($y = 0;$y -lt $currentPiece[$x].Count;$y++)
            {
                if ($currentPiece[$x][$y] -gt 0 -and
                   ($playingBoard[($x+$currentX),($y+$currentY)]) -gt 0)
                {
                    $collision = $true
                }
            }
        }

        if ($collision) { break }

        # erase old 
        if ($currentX -gt 0)
        {
            for ($x = 0;$x -lt $previousPiece.Count;$x++)
            {
                for ($y = 0;$y -lt $previousPiece[$x].Count;$y++)
                {
                    if ($previousPiece[$x][$y] -gt 0)
                    {
                        for ($i = 0; $i -lt $playAreaScaleY;$i++)
                        {
                            $XX = $playAreaTop+$x+$previousX
                            $YY = $playAreaLeft+($playAreaScaleY*($previousY+$y))+$i
                            Write-Output "$esc[$($XX);$($YY)H$esc[0;0;0m "
                        }
                    }
                }
            }
        }

        $previousX = $currentX
        $previousY = $currentY
        $previousPiece = $currentPiece

        for ($x = 0;$x -lt $currentPiece.Count;$x++)
        {
            for ($y = 0;$y -lt $currentPiece[$x].Count;$y++)
            {
                if ($currentPiece[$x][$y] -gt 0)
                {
                    $color = $currentPiece[$x][$y]+100
                    for ($i = 0; $i -lt $playAreaScaleY;$i++)
                    {
                        $XX = $playAreaTop+$x+$currentX
                        $YY = $playAreaLeft+($playAreaScaleY*($currentY+$y))+$i
                    
                        Write-Output "$esc[$($XX);$($YY)H$esc[$($color)m "
                    }
                }
            }
        }

        if ([console]::KeyAvailable)
        {
            $key = [System.Console]::ReadKey() 
            switch($key.Key)
            {
                UpArrow {
                    $flippedPiece = New-Object Object[] $currentPiece[0].Count
                    for ($j = 0;$j -lt $currentPiece[0].Count;$j++)
                    {
                        $flippedPiece[$j] = New-Object Object[] $currentPiece.Count
                        for ($k = 0;$k -lt $currentPiece.Count;$k++)
                        {
                            $flippedPiece[$j][$k] = $currentPiece[($currentPiece.Count-$k-1)][$j]                       
                        }
                    }

                    $flipCollision = $false

                    # check flipped piece for collision
                    for ($j=0;$j -lt $flippedPiece.Count;$j++)
                    {
                        for ($k=0;$k -lt $flippedPiece[0].Count;$k++)
                        {
                            if ($flippedPiece[$j][$k] -gt 0)
                            {
                                if ($currentX+$j -ge $playAreaHeight -or $currentY+$k -ge $playAreaWidth)
                                {
                                    $flipCollision = $true
                                }
                                elseif ($playingBoard[($currentX+$j),($currentY+$k)] -gt 0)
                                {
                                    $flipCollision = $true
                                }
                            }
                        }
                    }

                    if (!$flipCollision)
                    {
                        $currentPiece = $flippedPiece
                        $currentX--
                        $noWait=$true
                    }
                
                }
                Escape    { 
                    $DoExit = $true
                    break }
                LeftArrow { 
                    if ($currentY -gt 0)
                    {
                        $currentY--
                        $currentX--
                        $noWait = $true 
                    }
                }
                RightArrow { 
                    if ($currentY + $currentPiece[0].Count -lt $playAreaWidth)
                    {
                        $currentY++ 
                        $currentX--
                        $noWait = $true
                    }
                }
                DownArrow {
                    $noWait = $true
                    $score+=10
                }
                default { Write-Host $key.Key }
            
            }
        }

        if ($noWait)
        {
            $noWait = $false
        }
        else
        {
            Start-Sleep -Milliseconds $delay
        }

    }

    if ($currentX -eq 0) 
    {
        clear
        Write-Host "$esc[37;0mGAME OVER - Your score is $score at level $level with $totalLines"
        $name = Read-Host -Prompt "Enter your name?"
        $dataTable = New-Object System.Data.DataTable
        [void]$dataTable.Columns.Add("Name")
        [void]$dataTable.Columns.Add("Score")
        [void]$dataTable.Columns.Add("Level")
        [void]$dataTable.Columns.Add("Lines")
        if (!(Test-Path($highScoreFile)))
        {
            [void]$dataTable.Rows.Add($name,$score,$level,$totalLines)
            $dataTable | Select-Object Name,Score,Level,Lines | ConvertTo-Json | Set-Content -Path $highScoreFile
            $highScoreTable = Get-Content -Path $highScoreFile | ConvertFrom-Json
            
        }
        else
        {        
            $highScoretable = Get-Content -Path $highScoreFile | ConvertFrom-Json
            ForEach ($row in $highScoreTable)
            {
                [void]$dataTable.Rows.Add($row.Name,$row.Score,$row.Level,$row.Lines)
        
            }            
            [void]$dataTable.Rows.Add($name,$score,$level,$totalLines)
            $dataTable | Select-Object Name,Score,Level,Line | Sort-Object -Property Score -Descending | Select-Object -First 20 | ConvertTo-Json | Set-Content -Path $highScoreFile
        }
        
        Write-Host "High Scores"
        $dataTable | Sort-Object -Property Score -Descending | Select-Object -First 20 | Format-Table
        &pause
        return
    }
    for ($x = 0;$x -lt $previousPiece.Count;$x++)
    {
        for ($y = 0;$y -lt $previousPiece[$x].Count;$y++)
        {
            if ($previousPiece[$x][$y] -gt 0)
            {
                $playingBoard[($x+$previousX),($y+$previousY)] = $previousPiece[$x][$y]
            }
        }
    }

    # check for completed lines

    $completedLines = 0
    for ($x=0;$x -lt $playAreaHeight;$x++)
                                                                                                                                                    {
    $XX = $playAreaTop+$x
    $blockCount = 0
    for ($y=0;$y -lt $playAreaWidth;$y++)
    {
        if ($playingBoard[$x,$y] -gt 0) { $blockCount++ }
    }

    if ($blockCount -eq $playAreaWidth)
    {
        $completedLines++
        
        for ($c=0;$c -lt 7;$c++)
        {
            $color = 101+$c
            if ($c -eq 6) { $color = 0 } 
            for ($y = 0;$y -lt $playAreaWidth;$y++)
            {
                
                for ($i = 0; $i -lt $playAreaScaleY;$i++)
                {
                    $YY = $playAreaLeft+($playAreaScaleY*($y))+$i
                    Write-Output "$esc[$($XX);$($YY)H$esc[$($color)m "
                }
            }

            Start-Sleep -Milliseconds 10
        }

        # move blocks down after removed row
        for ($xx = $x;$xx -gt 0;$xx--)
        {
            for ($yy=0;$yy -lt $playAreaWidth;$yy++)
            {
                $playingBoard[$xx,$yy] = $playingBoard[($xx-1),$yy]                
            } 
                   
        }
    
    }
    }
    
    $totalLines+=$completedLines
    $levelLines+=$completedLines

    if ($levelLines -gt $level*5)
    {
        $level++
        if ($level -gt 10) { 
            $level = 10 
            $score += 10000
        }
        $levelLines = 0
    }
    if ($completedLines -gt 0)
    {
        switch ($completedLines)
        {
            1 { $score += 40 * ($level + 1)	}
            2 { $score += 100 * ($level + 1) }	
            3 { $score += 300 * ($level + 1) }
            4 { $score += 400 * ($level + 1) }
        }

        # redraw board after erases lines
        for ($x=0;$x -lt $playAreaHeight;$x++)
        {
            $XX = $playAreaTop+$x

            for ($y=0;$y -lt $playAreaWidth;$y++)
            {
                if ($playingBoard[$x,$y] -gt 0)
                {
                    $color = $playingBoard[$x,$y]+100
                }
                else
                {
                    $color = 0
                }
            
                for ($i = 0; $i -lt $playAreaScaleY;$i++)
                {
                    $YY = $playAreaLeft+($playAreaScaleY*($y))+$i                   
                    Write-Output "$esc[$($XX);$($YY)H$esc[$($color)m "
                }
            }
        }
    }
}