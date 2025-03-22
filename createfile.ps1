<#
.SYNOPSIS
Creates a file with speed statistics tracking and various write options.

.DESCRIPTION
Creates a file of specified size with performance metrics and different write modes.

.PARAMETER Path
Target file path.

.PARAMETER Size
File size (e.g., "100MB", "5GB").

.PARAMETER DataType
Data pattern: Random (secure random) or Zero (null bytes).

.PARAMETER WriteMode
Write method: Sequential or Random.

.PARAMETER Force
Overwrite existing file.

.EXAMPLE
.\CreateFile.ps1 -Path "D:\test.bin" -Size "1GB" -DataType Zero -WriteMode Sequential -Force
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [Parameter(Mandatory=$true)]
    [string]$Size,

    [ValidateSet("Random", "Zero")]
    [string]$DataType = "Random",

    [ValidateSet("Sequential", "Random")]
    [string]$WriteMode = "Sequential",

    [switch]$Force
)

function Parse-Size($sizeString) {
    if ($sizeString -match '^(\d+)(B|KB|MB|GB|TB)$') {
        $num = [double]$Matches[1]
        $unit = $Matches[2]
        
        switch ($unit) {
            'B'  { return $num }
            'KB' { return $num * 1KB }
            'MB' { return $num * 1MB }
            'GB' { return $num * 1GB }
            'TB' { return $num * 1TB }
        }
    }
    throw "Invalid size format. Use formats like '100MB', '5GB' etc."
}

try {
    # Initialize metrics
    $globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $speedMetrics = @()
    $sizeInBytes = [long](Parse-Size $Size)
    $bufferSize = 1MB

    # File management
    if (Test-Path $Path -PathType Leaf) {
        if ($Force) { Remove-Item $Path -Force }
        else { throw "File exists. Use -Force to overwrite." }
    }

    $directory = Split-Path $Path -Parent
    if (-not (Test-Path $directory)) { 
        New-Item -ItemType Directory -Path $directory | Out-Null 
    }

    # File operations
    $fileStream = [System.IO.File]::OpenWrite($Path)
    $rng = if ($DataType -eq "Random") { 
        [System.Security.Cryptography.RNGCryptoServiceProvider]::new() 
    }
    $buffer = New-Object byte[] $bufferSize

    # Main write process
    if ($WriteMode -eq "Sequential") {
        $totalWritten = [long]0
        while ($totalWritten -lt $sizeInBytes) {
            $chunkSize = [Math]::Min($bufferSize, [long]($sizeInBytes - $totalWritten))
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Заполнение буфера данными
            if ($DataType -eq "Random") {
                $rng.GetBytes($buffer)
            }
            else {
                [Array]::Clear($buffer, 0, $buffer.Length)
            }
            
            # Запись данных в файл
            $fileStream.Write($buffer, 0, $chunkSize)
            $totalWritten += $chunkSize
            
            # Расчет скорости
            $sw.Stop()
            $speedMBs = ($chunkSize / 1MB) / ($sw.Elapsed.TotalSeconds + 0.000001)
            $speedMetrics += $speedMBs
        }
    }
    else {
        $iterations = [Math]::Ceiling($sizeInBytes / $bufferSize)
        $rngPosition = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        
        for ($i = 0; $i -lt $iterations; $i++) {
            # Генерация позиции
            $positionBytes = New-Object byte[] 8
            $rngPosition.GetBytes($positionBytes)
            $position = [BitConverter]::ToUInt64($positionBytes, 0) % ($sizeInBytes - $bufferSize + 1)
            
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Заполнение буфера
            if ($DataType -eq "Random") {
                $rng.GetBytes($buffer)
            }
            else {
                [Array]::Clear($buffer, 0, $buffer.Length)
            }
            
            # Случайная запись
            $fileStream.Seek($position, [System.IO.SeekOrigin]::Begin)
            $fileStream.Write($buffer, 0, $bufferSize)
            
            # Расчет скорости
            $sw.Stop()
            $speedMBs = ($bufferSize / 1MB) / ($sw.Elapsed.TotalSeconds + 0.000001)
            $speedMetrics += $speedMBs
        }
        $rngPosition.Dispose()
    }

    # Calculate statistics
    $globalStopwatch.Stop()
    $totalTime = $globalStopwatch.Elapsed.TotalSeconds
    $avgSpeed = ($sizeInBytes / 1MB) / $totalTime
    
    $stats = [PSCustomObject]@{
        TotalSizeGB = [Math]::Round($sizeInBytes / 1GB, 2)
        TotalTime = [timespan]::FromSeconds($totalTime)
        AverageSpeedMBs = [Math]::Round($avgSpeed, 2)
        MaxSpeedMBs = [Math]::Round(($speedMetrics | Measure -Maximum).Maximum, 2)
        MinSpeedMBs = [Math]::Round(($speedMetrics | Measure -Minimum).Minimum, 2)
        MedianSpeedMBs = [Math]::Round(($speedMetrics | Sort-Object)[[int]($speedMetrics.Count/2)], 2)
    }

    # Display results
    Write-Host "`n=== Write Performance Summary ===" -ForegroundColor Cyan
    $stats | Format-List | Out-Host
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    if ($fileStream) { $fileStream.Close() }
    if ($rng) { $rng.Dispose() }
}
