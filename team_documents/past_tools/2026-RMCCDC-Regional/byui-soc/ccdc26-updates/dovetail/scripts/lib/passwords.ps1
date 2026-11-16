# CCDC26 Dovetail - Deterministic Password Generation
# Source: . "$PSScriptRoot\lib\passwords.ps1"

$script:WordList = @(
    "alpha","bravo","charlie","delta","echo","foxtrot","golf","hotel",
    "india","juliet","kilo","lima","mike","november","oscar","papa",
    "quebec","romeo","sierra","tango","uniform","victor","whiskey","xray",
    "yankee","zulu","apple","banana","cherry","dragon","eagle","falcon",
    "glacier","harbor","island","jungle","kayak","lemon","mango","neptune",
    "orange","piano","quartz","river","sunset","tiger","umbrella","violet",
    "walrus","xenon","yellow","zebra","anchor","beacon","castle","dolphin",
    "ember","flame","granite","horizon","ivory","jasper","kingdom","lantern",
    "marble","nebula","oasis","phoenix","quantum","raven","sapphire","thunder",
    "unicorn","vortex","willow","xylo","yonder","zenith","arctic","blazer",
    "cosmic","dagger","eclipse","frost","galaxy","hunter","inferno","jewel",
    "kraken","lotus","mystic","ninja","obsidian","prism","quest","rocket",
    "shadow","tempest","ultra","valiant","warrior","xeno","yeoman","zodiac",
    "atlas","blade","cipher","dynamo","enigma","fury","ghost","havoc"
)

function Get-DeterministicPassword {
    param(
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(Mandatory=$true)][string]$Salt,
        [int]$WordCount = 5
    )

    $combined = "$Salt$Username"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $hashBytes = $md5.ComputeHash($bytes)
    $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

    $words = @()
    $wlCount = $script:WordList.Count
    for ($i = 0; $i -lt $WordCount; $i++) {
        $start = ($i * 4) % $hashString.Length
        $seg = $hashString.Substring($start, [Math]::Min(4, $hashString.Length - $start))
        $val = [Convert]::ToInt32($seg, 16)
        $words += $script:WordList[$val % $wlCount]
    }

    return ($words -join "-") + "1"
}
