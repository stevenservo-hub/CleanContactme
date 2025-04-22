$InputFile = "customercontact.csv"
$OutputFile = "cleaneddata.csv"
$ArchiveFile = "cleaneddata.archive.csv"
$LastArchiveFile = "lastarchive.timestamp" # File to track the last archive date

$SyslogTag = "DataProcessor"

function Send-SyslogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Priority = "user.info"
    )
    & logger -t $SyslogTag -p $Priority $Message
}

if (-not (Test-Path $InputFile)) {
    $ErrorMessage = "Input file not found: $InputFile"
    Send-SyslogMessage -Message $ErrorMessage -Priority "user.error"
    Write-Error $ErrorMessage
    exit 1
}

$shouldArchive = $false
if (Test-Path $LastArchiveFile) {
    $lastArchiveDate = Get-Content -Path $LastArchiveFile | ForEach-Object { [datetime]$_ }
    if ((Get-Date) -gt $lastArchiveDate.AddDays(30)) {
        $shouldArchive = $true
    }
} else {
    $shouldArchive = $true
}

if ($shouldArchive -and (Test-Path $OutputFile)) {
    $outputFileContent = Get-Content -Path $OutputFile -ErrorAction SilentlyContinue
    $contentToArchive = $outputFileContent | Select-Object -Skip 1

    if ($contentToArchive) {
        Add-Content -Path $ArchiveFile -Value $contentToArchive -Encoding UTF8
        $ArchiveMessage = "Archived content of '$OutputFile' (excluding header) to '$ArchiveFile'."
        Send-SyslogMessage -Message $ArchiveMessage -Priority "user.info"

        (Get-Date).ToString("o") | Out-File -Path $LastArchiveFile -Force -Encoding UTF8
    }
}

if (-not (Test-Path $OutputFile)) {
    "PhoneNumber,Email,Message" | Out-File -Path $OutputFile -Encoding UTF8
}

function IsValidEmail {
    param (
        [string]$Email
    )
    return $Email -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}

Import-Csv -Path $InputFile | ForEach-Object {
    $phoneNumber = $_.PhoneNumber
    $email = $_.Email
    $message = $_.Message

    if (-not (IsValidEmail -Email $email)) {
        $WarningMessage = "Skipping row due to invalid email: '$($_ | ConvertTo-Csv -NoTypeInformation -Delimiter ',')'"
        Send-SyslogMessage -Message $WarningMessage -Priority "user.warning"
        return
    }

    $cleanedNumber = $phoneNumber -replace '\D', ''
    $truncatedMessage = if ($message.Length -gt 100) { 
        $message.Substring(0, 100) 
    } else { 
        $message 
    }

    $csvRow = New-Object PSObject -Property @{
        PhoneNumber = $cleanedNumber
        Email       = $email
        Message     = $truncatedMessage
    } | ConvertTo-Csv -NoTypeInformation -Delimiter ',' | Select-Object -Skip 1

    Add-Content -Path $OutputFile -Value $csvRow -Encoding UTF8
}

"" | Out-File -Path $InputFile -Encoding UTF8

$SuccessMessage = "Successfully processed $InputFile and updated $OutputFile."
Send-SyslogMessage -Message $SuccessMessage -Priority "user.info"
Write-Host $SuccessMessage
