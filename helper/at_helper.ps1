# AutoTranslator 翻訳ヘルパー
# ゲーム (Windower) とは別のプロセスで動き、data/queue/ の依頼ファイルを API で翻訳して結果ファイルを書く。
# ゲーム側は待たずに結果ファイルを確認するだけなので、翻訳中もゲームは止まらない。
#
#   依頼: data/queue/<id>.req  (UTF-8 JSON: id, text, target_lang, provider, system_prompt)
#   結果: data/queue/<id>.res  (UTF-8: 1 行目 OK/ERR, 2 行目 使った API, 3 行目以降 訳文 or エラー内容)
#
# 終了条件: data/queue/stop が置かれた / heartbeat ファイルが 30 秒更新されない (ゲーム終了・異常終了)

param(
    [Parameter(Mandatory = $true)][string]$AddonDir
)

$ErrorActionPreference = 'Stop'

$QueueDir      = Join-Path $AddonDir 'data\queue'
$SettingsPath  = Join-Path $AddonDir 'filler.xml'
$StopFile      = Join-Path $QueueDir 'stop'
$HeartbeatFile = Join-Path $QueueDir 'heartbeat'
$LogFile       = Join-Path $QueueDir 'helper.log'

$HeartbeatTimeoutSec = 30     # ゲーム側の合図がこの秒数途絶えたら終了
$PollMs              = 100    # 依頼ファイルを確認する間隔
$HttpTimeoutMs       = 8000   # API 1 社あたりの待ち時間
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log([string]$msg) {
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 100KB) { Remove-Item $LogFile -Force }
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg + "`r`n"
        [IO.File]::AppendAllText($LogFile, $line, $Utf8NoBom)
    } catch {}
}

# 二重起動を防ぐ (読み込み直し直後は、前のヘルパーの終了を少し待つ)
$mutex = New-Object System.Threading.Mutex($false, 'AutoTranslatorHelper')
try {
    if (-not $mutex.WaitOne(3000)) { exit 0 }
} catch [System.Threading.AbandonedMutexException] {
    # 前のヘルパーが異常終了していた場合。所有権は取れているのでそのまま続ける
}

# API キーは毎回 filler.xml から読む (キーを変えてもヘルパーの再起動が要らない)
# Windower の config が書く filler.xml には <1>rmt</1> のような XML として不正なタグがあるため、
# XML としては読まず、<api_keys> の中から各キーだけを取り出す。
# ※ エラー文にはファイルの中身 (キー) が含まれることがあるので、ログには書かない
function Get-ApiKeys {
    $keys = @{ deepl = ''; openai = ''; claude = '' }
    try {
        $content = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8)
        $m = [regex]::Match($content, '<api_keys>(.*?)</api_keys>', 'Singleline')
        if (-not $m.Success) { Write-Log 'filler.xml: api_keys not found'; return $keys }
        foreach ($p in @('deepl', 'openai', 'claude')) {
            $km = [regex]::Match($m.Groups[1].Value, '<' + $p + '>(.*?)</' + $p + '>', 'Singleline')
            if ($km.Success) {
                $v = $km.Groups[1].Value.Trim().Trim('"', "'")
                if ($v -ne '' -and $v -notmatch '^YOUR_') { $keys[$p] = $v }
            }
        }
    } catch {
        Write-Log 'filler.xml read failed'
    }
    return $keys
}

# HTTP POST。応答は文字コードの指定に頼らず UTF-8 として読む (PowerShell 5.1 の文字化け対策)
function Invoke-JsonPost([string]$url, [hashtable]$headers, $bodyObj) {
    $json  = $bodyObj | ConvertTo-Json -Depth 8 -Compress
    $bytes = $Utf8NoBom.GetBytes($json)

    $req = [Net.HttpWebRequest]::Create($url)
    $req.Method = 'POST'
    $req.ContentType = 'application/json'
    $req.UserAgent = 'AutoTranslator-Helper/1.0'
    $req.Timeout = $HttpTimeoutMs
    $req.ReadWriteTimeout = $HttpTimeoutMs
    foreach ($k in $headers.Keys) { $req.Headers[$k] = $headers[$k] }
    $req.ContentLength = $bytes.Length

    try {
        $s = $req.GetRequestStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.Close()
        $resp = $req.GetResponse()
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
        if ($ex -and $ex.Response) { throw ('HTTP ' + [int]$ex.Response.StatusCode) }
        if ($ex) { throw $ex.Message }
        throw $_.Exception.Message
    }

    $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
    $text = $sr.ReadToEnd()
    $sr.Close()
    $resp.Close()
    return ($text | ConvertFrom-Json)
}

# DeepL の削除用 (応答本文なし)
function Invoke-HttpDelete([string]$url, [hashtable]$headers) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Method = 'DELETE'
    $req.Timeout = $HttpTimeoutMs
    foreach ($k in $headers.Keys) { $req.Headers[$k] = $headers[$k] }
    $resp = $req.GetResponse()
    $resp.Close()
}

function Get-Sha256([string]$s) {
    $sha = New-Object System.Security.Cryptography.SHA256Managed
    try { return [BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($s))).Replace('-', '') } finally { $sha.Dispose() }
}

# ---------------------------------------------------------------------------
# DeepL 用語集 (FFXI の固有名詞をゲームと同じ名前で訳させる)。翻訳の向きごとに 1 つずつ持つ
#   英語 → 日本語: data/glossary_en_ja.tsv (英語名<TAB>日本語名) / 登録情報 data/deepl_glossary.txt
#   日本語 → 英語: data/glossary_ja_en.tsv (日本語名<TAB>英語名) / 登録情報 data/deepl_glossary_ja_en.txt
#   登録情報は「指紋<TAB>ID」。表やキーが変わったときだけ登録し直す
# ---------------------------------------------------------------------------
#   ※ 今の DeepL のプランでは用語集は 1 つまでしか作れないため、使うのは英語 → 日本語だけ。
#     日本語 → 英語は、ゲーム側で地名を英語名に置き換えてから送る (glossary.lua の replace_ja)
$GlossaryPairs = @{
    'en-ja' = @{ Tsv = (Join-Path $AddonDir 'data\glossary_en_ja.tsv'); State = (Join-Path $AddonDir 'data\deepl_glossary.txt'); Source = 'en'; Target = 'ja' }
}
$script:GlossaryCache = @{}   # [向き] = @{ Id; Fingerprint }

function Get-DeepLBase([string]$key) {
    if ($key.EndsWith(':fx')) { return 'https://api-free.deepl.com' }
    return 'https://api.deepl.com'
}

function Get-DeepLGlossaryId([string]$key, [string]$pairName) {
    $pair = $GlossaryPairs[$pairName]
    if (-not $pair -or -not (Test-Path -LiteralPath $pair.Tsv)) { return $null }
    $tsv = [IO.File]::ReadAllText($pair.Tsv, [Text.Encoding]::UTF8).Trim()
    if ($tsv -eq '') { return $null }
    # 指紋は「表 + キー」から作る (キーそのものは保存しない)
    $fingerprint = Get-Sha256 ($tsv + "`n" + $key)
    $cached = $script:GlossaryCache[$pairName]
    if ($cached -and $cached.Fingerprint -eq $fingerprint) { return $cached.Id }

    $oldId = $null
    if (Test-Path -LiteralPath $pair.State) {
        $parts = ([IO.File]::ReadAllText($pair.State, [Text.Encoding]::UTF8).Trim()) -split "`t"
        if ($parts.Count -eq 2) {
            if ($parts[0] -eq $fingerprint) {
                $script:GlossaryCache[$pairName] = @{ Id = $parts[1]; Fingerprint = $fingerprint }
                return $parts[1]
            }
            $oldId = $parts[1]
        }
    }

    $base = Get-DeepLBase $key
    $auth = @{ 'Authorization' = 'DeepL-Auth-Key ' + $key }
    if ($oldId) { try { Invoke-HttpDelete ($base + '/v2/glossaries/' + $oldId) $auth } catch {} }

    $g = Invoke-JsonPost ($base + '/v2/glossaries') $auth @{
        name = 'AutoTranslator FFXI ' + $pairName; source_lang = $pair.Source; target_lang = $pair.Target
        entries = $tsv; entries_format = 'tsv'
    }
    $id = [string]$g.glossary_id
    $script:GlossaryCache[$pairName] = @{ Id = $id; Fingerprint = $fingerprint }
    [IO.File]::WriteAllText($pair.State, ($fingerprint + "`t" + $id), $Utf8NoBom)
    Write-Log ('deepl glossary created (' + $pairName + '): ' + $g.entry_count + ' entries')
    return $id
}

function Reset-DeepLGlossary([string]$pairName) {
    $script:GlossaryCache.Remove($pairName)
    try { [IO.File]::Delete($GlossaryPairs[$pairName].State) } catch {}
}

# <x>[定型文]</x> の印と XML 用の記号を外して、普通の文に戻す
function ConvertFrom-Marked([string]$s) {
    return ($s -replace '</?x>', '').Replace('&lt;', '<').Replace('&gt;', '>').Replace('&amp;', '&')
}

# 翻訳の向き: 'en-ja' (英語→日本語) / 'ja-en' (日本語→英語)
function Get-PairName($r) {
    if ($r.target_lang -eq 'en') { return 'ja-en' }
    return 'en-ja'
}

function Invoke-DeepL([string]$key, $r, [bool]$useGlossary) {
    $pairName = Get-PairName $r
    # 英語は米国英語を指定する (DeepL では "EN" 単独の指定は非推奨)
    $target = if ($pairName -eq 'ja-en') { 'EN-US' } else { 'JA' }
    $source = if ($pairName -eq 'ja-en') { 'JA' } else { 'EN' }
    $isXml = ($r.xml -eq $true)
    $body = @{ text = @([string]$r.text); target_lang = $target }
    # 同じチャットの直前の発言。訳されず、文字数にも数えられないが、略語や言い回しの判断に使われる
    if ([string]$r.context -ne '') { $body.context = [string]$r.context }
    if ($pairName -eq 'ja-en') {
        # 日本語の文に英語名 (地名・定型文) を入れて送るので、英語の文と取り違えないよう元の言語を指定する
        $body.source_lang = 'JA'
    }
    if ($isXml) {
        # <x>..</x> の中 (定型文の表記) は訳さずに残してもらう。
        # 翻訳先の言語が混ざると DeepL が元の言語を取り違えて訳さないことがあるので、元の言語を指定する
        $body.tag_handling = 'xml'
        $body.ignore_tags = @('x')
        $body.source_lang = $source
    }
    if ($useGlossary -and $GlossaryPairs.ContainsKey($pairName)) {
        $gid = $null
        try { $gid = Get-DeepLGlossaryId $key $pairName } catch { Write-Log ('deepl glossary unavailable (' + $pairName + '): ' + $_.Exception.Message) }
        if ($gid) {
            # 用語集を使うときは元の言語の指定が必要
            $body.source_lang = $source
            $body.glossary_id = $gid
        }
    }
    $res = Invoke-JsonPost ((Get-DeepLBase $key) + '/v2/translate') @{ 'Authorization' = 'DeepL-Auth-Key ' + $key } $body
    $out = [string]$res.translations[0].text
    if ($isXml) {
        # DeepL は印の前後に英語風の空白を入れるので、日本語どうしの間の空白は詰めてから印を外す
        $out = $out -replace '</x>\s+(?=[^\x00-\x7F])', '</x>' -replace '(?<=[^\x00-\x7F])\s+<x>', '<x>'
        $out = ConvertFrom-Marked $out
    }
    if ($pairName -eq 'ja-en') {
        # 定型文の英語名が複数形にされることがある ([100 Byne Bill] → [100 Byne Bills]) ので、元の表記に戻す
        $src = [string]$r.text
        $out = [regex]::Replace($out, '\[([^\[\]]+?)(?:es|s)\]', {
            param($m)
            $orig = '[' + $m.Groups[1].Value + ']'
            if ($src.Contains($orig)) { return $orig }
            return $m.Value
        })
    }
    return $out
}

# OpenAI / Claude 用の指示文。文に含まれる固有名詞の対応を書き足す
function Get-SystemPrompt($r) {
    $prompt = [string]$r.system_prompt
    $terms = [string]$r.terms
    if ($terms -ne '') {
        $prompt += "`nAlways translate these FFXI terms exactly as given, and keep any [bracketed] terms unchanged: " + $terms
    }
    $context = [string]$r.context
    if ($context -ne '') {
        $prompt += "`nRecent lines in the same chat, for context only (do not translate them):`n" + $context
    }
    return $prompt
}

function Invoke-Provider([string]$provider, [string]$key, $r) {
    # OpenAI / Claude には印を外した文を送る (定型文は [日本語名] の形で入っている)
    $plainText = if ($r.xml -eq $true) { ConvertFrom-Marked ([string]$r.text) } else { [string]$r.text }

    switch ($provider) {
        'deepl' {
            try {
                return (Invoke-DeepL $key $r $true)
            } catch {
                # 用語集が消されていた等。用語集を作り直す準備をして、今回は用語集なしで訳す
                $pairName = Get-PairName $r
                if ($script:GlossaryCache[$pairName]) {
                    Write-Log ('deepl with glossary failed, retry without: ' + $_.Exception.Message)
                    Reset-DeepLGlossary $pairName
                    return (Invoke-DeepL $key $r $false)
                }
                throw
            }
        }
        'openai' {
            $body = @{
                model = 'gpt-4o-mini'
                messages = @(
                    @{ role = 'system'; content = (Get-SystemPrompt $r) },
                    @{ role = 'user'; content = $plainText }
                )
                max_tokens = 60
                temperature = 0.0
            }
            $res = Invoke-JsonPost 'https://api.openai.com/v1/chat/completions' @{ 'Authorization' = 'Bearer ' + $key } $body
            return [string]$res.choices[0].message.content
        }
        'claude' {
            $body = @{
                model = 'claude-haiku-4-5'
                system = (Get-SystemPrompt $r)
                messages = @(@{ role = 'user'; content = $plainText })
                max_tokens = 60
                temperature = 0.0
            }
            $res = Invoke-JsonPost 'https://api.anthropic.com/v1/messages' @{ 'x-api-key' = $key; 'anthropic-version' = '2023-06-01' } $body
            return [string]$res.content[0].text
        }
    }
    throw ('unknown provider ' + $provider)
}

function Write-Result([string]$id, [string]$content) {
    $tmp = Join-Path $QueueDir ($id + '.res.tmp')
    $dst = Join-Path $QueueDir ($id + '.res')
    [IO.File]::WriteAllText($tmp, $content, $Utf8NoBom)
    Move-Item -LiteralPath $tmp -Destination $dst -Force
}

function Invoke-Request([IO.FileInfo]$file) {
    $id = $file.BaseName
    try {
        $raw = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        Remove-Item -LiteralPath $file.FullName -Force
        $r = $raw | ConvertFrom-Json
    } catch {
        Write-Log ('bad request ' + $id + ': ' + $_.Exception.Message)
        try { Remove-Item -LiteralPath $file.FullName -Force } catch {}
        Write-Result $id ("ERR`n`nbad request")
        return
    }

    $keys = Get-ApiKeys
    $primary = ([string]$r.provider).ToLower()
    $order = switch ($primary) {
        'openai' { @('openai', 'deepl', 'claude') }
        'claude' { @('claude', 'deepl', 'openai') }
        default  { @('deepl', 'openai', 'claude') }
    }

    $errors = @()
    foreach ($p in $order) {
        if ($keys[$p] -eq '') { continue }
        try {
            $text = (Invoke-Provider $p $keys[$p] $r)
            if ($text -and $text.Trim() -ne '') {
                Write-Result $id ("OK`n" + $p + "`n" + $text.Trim())
                return
            }
            $errors += ($p.ToUpper() + ' (empty)')
        } catch {
            $errors += ($p.ToUpper() + ' (' + $_.Exception.Message + ')')
        }
    }

    $msg = if ($errors.Count -gt 0) { $errors -join ' / ' } else { 'API keys missing' }
    Write-Log ('translate failed ' + $id + ': ' + $msg)
    Write-Result $id ("ERR`n`n" + $msg)
}

try {
    Write-Log 'helper started'

    # 前回の残りファイル (1 分以上前のもの) を片付ける
    Get-ChildItem -LiteralPath $QueueDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.req', '.res', '.tmp' -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # 起動した回の番号を覚える。heartbeat の番号が変わったら、アドオンが読み込み直されたので終了する
    # (読み込み直しでは停止の合図ファイルがすぐ消されるため、合図だけでは古いヘルパーが残ってしまう)
    $mySession = ''
    try { $mySession = [IO.File]::ReadAllText($HeartbeatFile).Trim() } catch {}
    Write-Log ('session ' + $mySession)

    while ($true) {
        if (Test-Path -LiteralPath $StopFile) { Write-Log 'stop file found'; break }
        if (-not (Test-Path -LiteralPath $HeartbeatFile)) { Write-Log 'heartbeat missing'; break }
        $currentSession = ''
        try { $currentSession = [IO.File]::ReadAllText($HeartbeatFile).Trim() } catch { $currentSession = $mySession }
        if ($currentSession -ne $mySession) { Write-Log 'new session started, exiting'; break }
        $age = ((Get-Date) - (Get-Item -LiteralPath $HeartbeatFile).LastWriteTime).TotalSeconds
        if ($age -gt $HeartbeatTimeoutSec) { Write-Log 'heartbeat timeout'; break }

        $reqs = Get-ChildItem -LiteralPath $QueueDir -Filter '*.req' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
        foreach ($f in $reqs) { Invoke-Request $f }

        Start-Sleep -Milliseconds $PollMs
    }
} catch {
    Write-Log ('helper crashed: ' + $_.Exception.Message)
} finally {
    Write-Log 'helper stopped'
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
