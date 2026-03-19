param(
    [string]$InputFile,
    [string]$OutputFile
)

$reader = [System.IO.File]::OpenText($InputFile)
$writer = [System.IO.StreamWriter]::new($OutputFile)

while ($null -ne ($line = $reader.ReadLine())) {
    $fields = $line -split ','
    
    for ($i = 0; $i -lt $fields.Length; $i++) {
        # Left-align by trimming leading spaces
        $fields[$i] = $fields[$i].TrimStart()
        
        # Quote fields that contain commas
        if ($fields[$i] -match ',') {
            $fields[$i] = '"' + $fields[$i] + '"'
        }
        
        # Add $ to price columns (Cost=12, MSRP=13, SellingPrice=14)
        if ($i -eq 12 -or $i -eq 13 -or $i -eq 14) {
            if ($fields[$i]) {
                if ($fields[$i].StartsWith('"')) {
                    # If already quoted, add $ inside the quotes
                    $fields[$i] = '"$' + $fields[$i].Substring(1, $fields[$i].Length - 2) + '"'
                } else {
                    $fields[$i] = '$' + $fields[$i]
                }
            }
        }
    }
    
    $writer.WriteLine($fields -join ',')
}

$reader.Close()
$writer.Close()
