# AutoTranslator

FINAL FANTASY XI (Windower 4) 用の、チャット自動翻訳アドオンです。
English follows the Japanese section. → [English](#english)

---

## 日本語

### できること

- **会話のチャットを自動で翻訳**して、チャットログに `発言者 < 訳文` の形で表示します。
  - 対象: say / shout / yell / tell / party / リンクシェル 1・2 / ユニティ
  - システムメッセージ、NPC の会話、戦闘ログ、/echo、ほかのアドオンの表示は翻訳しません。
- **英語 → 日本語** と **日本語 → 英語** の両方に対応しています（`//at lang ja` / `//at lang en`）。
- **翻訳中もゲームが止まりません。** 翻訳は別のプログラム（PowerShell の翻訳ヘルパー）が行います。
- **エリア名をゲームの正式な名前で訳します。**
  - 例: `lets go to Norg` → 「ノーグに行こう」（DeepL だけだと「ノルグ」「ノルウェー」になります）
  - 例: `ジュノ港で待ち合わせしましょう` → `Let's meet up at Port Jeuno.`
- **定型文辞書（Tab 変換）をゲームと同じ表記で表示します。**
  - 例: `[at]100 Byne Bill[/at]` → `[100バイン紙幣]`
  - 定型文だけの発言（yell の売買の行など）は、API を使わずにすぐ表示します。
- **FF11 のスラング・略語を、分かる言葉にしてから翻訳します。**（v3.2.0）
  - 例: `voke the mob` → 「敵を挑発する」（DeepL だけだと「暴徒を煽る」になります）
  - 例: `lf1m for omen, need whm` → 「オーメンのメンバーをあと1名募集しています。白魔道士が必要です。」
  - ジョブ名（`whm` `cor` `brd` …）や `sc`（連携）、`th`（トレジャーハンター）など 60 語ほどを最初から登録しています（`data/slang.xml`）。
  - 同じ略語でも意味が変わるものは、同じ発言や直前の発言の言葉を見て使い分けます。例: `mb` は、連携の話の中なら「マジックバースト」、それ以外は「my bad（ごめん）」。
  - 略語は `//at slang add <略語> <意味>` で追加できます。意味を日本語で書くとそのまま訳文に入り、英語で書くと翻訳サービスがその英語を訳します。
- **直前の発言を参考にして訳します。**（v3.2.0）同じチャットの直前の発言（最大 3 行・2 分以内）を、翻訳サービスに参考情報として渡します。DeepL では、参考情報は訳されず、文字数にも数えられません。
- 一度翻訳した文は覚えておき、2 回目からはすぐに表示します。
- 翻訳サービスは **DeepL**（おすすめ）、**OpenAI**、**Claude** から選べます。うまくいかないときは、キーが設定されているほかのサービスを順に試します。

### 必要なもの

**追加でインストールするソフトウェアや Lua のライブラリはありません。** 次のものがそろっていれば動きます。

| 必要なもの | 説明 | 入っていない・動かないとき |
|---|---|---|
| Windower 4 | 使う Lua のライブラリ（`config` `texts` `resources` `ltn12`）は Windower に付属しています | Windower を起動して最新の状態に更新してください |
| Windows 10 / 11 | 下の 2 つが最初から入っています | — |
| Windows PowerShell 5.1 | 翻訳ヘルパー（`helper/at_helper.ps1`）を動かします | Windows 10 / 11 には標準で入っています。古い Windows では「Windows Management Framework 5.1」が必要です |
| VBScript | 翻訳ヘルパーを、画面を出さずに起動するのに使います（`helper/start_helper.vbs`） | 下の「VBScript が無効になっている場合」を見てください |
| インターネット接続 | 翻訳サービス（DeepL など）に問い合わせます | ウイルス対策ソフトやファイアウォールが PowerShell の通信を止めていないか確認してください |
| 翻訳サービスの API キー | どれか 1 つ。下の「API キーの作り方」を参照 | — |

#### VBScript が無効になっている場合

Microsoft は VBScript を段階的に廃止する予定で、Windows 11 の新しい版では「オプション機能」になっています（多くの場合、最初は有効です）。AutoTranslator を読み込んでも翻訳されず、`[AutoTranslator API Error] no response from translator helper (timeout)` と出るときは、次を確認してください。

1. Windows の「設定」→「システム」→「オプション機能」を開きます。
2. 「VBSCRIPT」が一覧にあるか確認します。無ければ「機能を表示（追加）」から「VBSCRIPT」を追加し、パソコンを再起動します。

#### ウイルス対策ソフトについて

翻訳ヘルパーは「画面に出ない PowerShell がインターネットに接続する」という動きをするため、ウイルス対策ソフトによっては止められることがあります。止められた場合は、`Windower/addons/AutoTranslator/helper/` フォルダを除外（許可）の対象に加えてください。中身はすべてテキストのスクリプトなので、事前に内容を確認できます。

### API キーの作り方

| サービス | 登録・プラン | API キーを作るページ |
|---|---|---|
| **DeepL**（おすすめ） | https://www.deepl.com/pro-api | https://www.deepl.com/your-account/keys |
| **OpenAI** | https://platform.openai.com/signup | https://platform.openai.com/api-keys |
| **Anthropic (Claude)** | https://console.anthropic.com/ | https://console.anthropic.com/settings/keys |

- **DeepL**: 「DeepL API Free（無料版）」に登録すると、毎月一定の文字数まで無料で翻訳できます。登録後、「API キー」のページでキーをコピーします（無料版のキーは末尾が `:fx`）。
- **OpenAI / Anthropic**: アカウントを作り、支払い方法（クレジット）を登録してから、API キーのページで新しいキーを作ります。キーは作ったときに一度しか表示されないので、すぐにコピーしてください。利用した分だけ料金がかかります。
- 料金・無料枠・登録の手順は変わることがあります。最新の情報は各サービスのページで確認してください。

### 入れ方

1. このフォルダを `Windower/addons/AutoTranslator/` に置きます。
   （`Windower/addons/AutoTranslator/AutoTranslator.lua` となるように）
2. 設定ファイルを作ります。次のどちらかの方法で作れます。
   - `data/filler.xml.example` をコピーして、**アドオンのフォルダ直下**に `filler.xml` という名前で置く
   - または、ゲーム内で一度 `//lua l autotranslator` を打つ（`filler.xml` が自動で作られます）
3. ゲーム内で `//lua u autotranslator` を打って、いったん外します。
4. `filler.xml` をメモ帳などで開き、使うサービスの API キーを書き込んで保存します。
   ```xml
   <api_keys>
       <deepl>ここに DeepL の API キー</deepl>
       <openai>YOUR_OPENAI_API_KEY</openai>
       <claude>YOUR_CLAUDE_API_KEY</claude>
   </api_keys>
   ```
   - 使わないサービスは `YOUR_...` のままで構いません。
   - DeepL 無料版のキーは末尾が `:fx` です。自動で無料版の窓口を使います。
5. ゲーム内で `//lua l autotranslator` を打って読み込みます。

> **注意:** AutoTranslator を読み込んだまま `filler.xml` を書き換えると、アドオンが設定を保存したときに古い内容で上書きされることがあります。書き換えるときは、必ず先に `//lua u autotranslator` で外してください。

### コマンド

| コマンド | 内容 |
|---|---|
| `//at lang ja` | 英語 → 日本語に翻訳する（日本語を使う人向け） |
| `//at lang en` | 日本語 → 英語に翻訳する（英語を使う人向け） |
| `//at provider deepl` / `openai` / `claude` | 最初に使う翻訳サービスを選ぶ |
| `//at test <文>` | 翻訳を試す（例: `//at test good morning`） |
| `//at add <単語> <訳>` | 辞書に追加する（辞書にある発言は API を使わずに訳します） |
| `//at del <単語>` | 辞書から削除する |
| `//at dict` | 辞書の一覧を表示する |
| `//at mode <種類...>` | 翻訳するチャットの種類を選ぶ（例: `//at mode party ls tell`）。種類: say shout yell tell party ls unity echo |
| `//at mode status` | 翻訳するチャットの種類を表示する |
| `//at block <名前>` / `//at unblock <名前>` | その人の発言を翻訳しない／元に戻す（`//at block` だけで一覧を表示） |
| `//at word add <語>` / `//at word del <語>` | その語を含む発言を翻訳しない（NG ワード） |
| `//at slang add <略語> <意味>` / `//at slang del <略語>` | スラング・略語の辞書に追加／削除する（例: `//at slang add omw on my way`） |
| `//at slang list` / `//at slang reload` | スラングの辞書を表示する／`data/slang.xml` を書き換えたあと読み込み直す |
| `//at typo add <誤字> <正しい綴り>` | よくある誤字の補正表に追加する（`del` / `list` も同じ。表は `data/typo.xml`） |
| `//at hud` | 翻訳結果を表示する小さな画面の ON / OFF（`//at hud reset` で位置を戻す） |
| `//at toggle` | 翻訳の ON / OFF |

### しくみ

```
ゲーム (Lua)                                 翻訳ヘルパー (PowerShell, 画面なし)
  チャットを受け取る
  辞書・キャッシュにあればすぐ表示
  無ければ data/queue/<id>.req を書く  ───▶  依頼を見つけて API に問い合わせる
  0.1 秒ごとに結果を確認             ◀───  data/queue/<id>.res を書く
  結果をチャットに表示
```

- 翻訳ヘルパー（`helper/at_helper.ps1`）は、AutoTranslator を読み込んだときに `helper/start_helper.vbs` から画面を出さずに起動します。
- AutoTranslator を外したとき、読み込み直したとき、ゲームを終了したとき（30 秒後）に、翻訳ヘルパーは自分で終了します。
- エリア名は Windower の一覧（`res/zones.lua`, `res/regions.lua`）から、定型文は `res/auto_translates.lua`、`res/items.lua` などから日本語名・英語名を引きます。
- 英語 → 日本語では、エリア名の対応表を **DeepL の用語集** として自動で登録して使います。
  - DeepL 無料版では用語集を 1 つしか作れないため、日本語 → 英語では用語集を使わず、送る前に地名を英語名に置き換えます。
  - 用語集の登録情報は `data/deepl_glossary.txt` に保存されます（API キーが変わったときは自動で登録し直します）。
- 翻訳ヘルパーの動きは `data/queue/helper.log` に記録されます（API キーは記録しません）。

### 注意

- **API キーは `filler.xml` に平文で保存されます。** `filler.xml` は `.gitignore` で除外しています。GitHub などに上げないでください。
- 翻訳サービスの利用料金・文字数の上限は、各サービスの規約に従います。
- Windower の Lua（5.1）では ffi が使えないため、`src/` と `libs/native_bridge.lua` のネイティブ DLL による翻訳は使われません（翻訳ヘルパーが代わりに動きます）。
- OpenAI / Claude で使うモデル名は `helper/at_helper.ps1` の中にあります。提供が終わったモデルの場合は書き換えてください。

### ライセンス

MIT License です。詳しくは [LICENSE](LICENSE) を見てください。

---

<a id="english"></a>

## English

### Features

- **Automatically translates conversation chat** and shows it in the chat log as `Speaker < translation`.
  - Translated: say / shout / yell / tell / party / linkshell 1 & 2 / unity
  - Not translated: system messages, NPC dialogue, battle logs, /echo, and output from other addons.
- Works in **both directions: English → Japanese** and **Japanese → English** (`//at lang ja` / `//at lang en`).
- **The game never freezes while translating.** Translation runs in a separate program (a PowerShell translator helper).
- **Area names are translated using the official in-game names.**
  - e.g. `lets go to Norg` → 「ノーグに行こう」 (DeepL alone gives "ノルグ" or "ノルウェー")
  - e.g. `ジュノ港で待ち合わせしましょう` → `Let's meet up at Port Jeuno.`
- **Auto-translate phrases (Tab completion) are shown exactly as the game writes them.**
  - e.g. `[at]100 Byne Bill[/at]` → `[100バイン紙幣]`
  - Messages made only of auto-translate phrases (such as yell trade lines) are shown instantly without calling an API.
- **FFXI slang and abbreviations are rewritten into plain words before translating.** (v3.2.0)
  - e.g. `voke the mob` → 「敵を挑発する」 (DeepL alone gives "暴徒を煽る", "incite the rioters")
  - e.g. `lf1m for omen, need whm` → 「オーメンのメンバーをあと1名募集しています。白魔道士が必要です。」
  - About 60 terms are registered by default (`data/slang.xml`): job names (`whm` `cor` `brd` …), `sc` (skillchain), `th` (Treasure Hunter), and more.
  - Abbreviations with more than one meaning are resolved from the same message or the previous ones. e.g. `mb` becomes "Magic Burst" when skillchains are being discussed, and "my bad" otherwise.
  - Add your own with `//at slang add <abbreviation> <meaning>`. A Japanese meaning is inserted into the translation as is; an English meaning is translated by the service.
- **Previous messages are used as context.** (v3.2.0) Up to 3 earlier lines from the same chat (within 2 minutes) are passed to the translation service as reference. With DeepL, this context is not translated and is not counted toward your character usage.
- Translations are cached, so the same message appears instantly the second time.
- Choose your translation service: **DeepL** (recommended), **OpenAI**, or **Claude**. If one fails, the other services that have a key are tried in order.

### Requirements

**No additional software or Lua libraries need to be installed.** It works as long as you have the following:

| Requirement | Description | If it is missing or not working |
|---|---|---|
| Windower 4 | The Lua libraries used (`config`, `texts`, `resources`, `ltn12`) come with Windower | Start Windower and let it update to the latest version |
| Windows 10 / 11 | Includes the next two items | — |
| Windows PowerShell 5.1 | Runs the translator helper (`helper/at_helper.ps1`) | Included with Windows 10 / 11. Older Windows needs "Windows Management Framework 5.1" |
| VBScript | Starts the translator helper without showing a window (`helper/start_helper.vbs`) | See "If VBScript is disabled" below |
| Internet connection | Used to contact the translation service (DeepL, etc.) | Check that your antivirus or firewall is not blocking PowerShell's network access |
| A translation service API key | At least one. See "Getting an API key" below | — |

#### If VBScript is disabled

Microsoft plans to phase out VBScript, and newer versions of Windows 11 make it an "optional feature" (usually enabled by default). If nothing is translated after loading AutoTranslator and you see `[AutoTranslator API Error] no response from translator helper (timeout)`, check the following:

1. Open Windows **Settings** → **System** → **Optional features**.
2. Check that "VBSCRIPT" is in the list. If it is not, add "VBSCRIPT" via **View features (Add a feature)** and restart your PC.

#### About antivirus software

The translator helper is "a PowerShell script with no window that connects to the internet", so some antivirus software may block it. If that happens, add the `Windower/addons/AutoTranslator/helper/` folder to your antivirus exclusions (allow list). Everything in it is a plain-text script, so you can review it beforehand.

### Getting an API key

| Service | Sign-up / plans | Create an API key |
|---|---|---|
| **DeepL** (recommended) | https://www.deepl.com/pro-api | https://www.deepl.com/your-account/keys |
| **OpenAI** | https://platform.openai.com/signup | https://platform.openai.com/api-keys |
| **Anthropic (Claude)** | https://console.anthropic.com/ | https://console.anthropic.com/settings/keys |

- **DeepL**: Sign up for "DeepL API Free" to translate a set number of characters per month at no cost. After signing up, copy your key from the "API keys" page (free-plan keys end with `:fx`).
- **OpenAI / Anthropic**: Create an account, add a payment method (credits), then create a new key on the API keys page. The key is shown only once when it is created, so copy it right away. You pay for what you use.
- Prices, free quotas, and sign-up steps may change. Check each service's site for the latest information.

### Installation

1. Put this folder in `Windower/addons/AutoTranslator/`
   (so that the path is `Windower/addons/AutoTranslator/AutoTranslator.lua`).
2. Create the settings file in one of these ways:
   - Copy `data/filler.xml.example` and save it as `filler.xml` **directly in the addon folder**, or
   - Type `//lua l autotranslator` once in game (`filler.xml` is created automatically).
3. Type `//lua u autotranslator` in game to unload the addon.
4. Open `filler.xml` in a text editor, enter the API key for the service you use, and save.
   ```xml
   <api_keys>
       <deepl>your DeepL API key here</deepl>
       <openai>YOUR_OPENAI_API_KEY</openai>
       <claude>YOUR_CLAUDE_API_KEY</claude>
   </api_keys>
   ```
   - Leave `YOUR_...` for services you do not use.
   - DeepL free-plan keys end with `:fx`; the free endpoint is used automatically.
5. Type `//lua l autotranslator` in game to load the addon.

> **Note:** If you edit `filler.xml` while AutoTranslator is loaded, the addon may overwrite your changes with the old settings when it saves. Always unload it first with `//lua u autotranslator`.

### Commands

| Command | Description |
|---|---|
| `//at lang ja` | Translate English → Japanese (for Japanese players) |
| `//at lang en` | Translate Japanese → English (for English players) |
| `//at provider deepl` / `openai` / `claude` | Choose the translation service to try first |
| `//at test <text>` | Test a translation (e.g. `//at test good morning`) |
| `//at add <word> <translation>` | Add a dictionary entry (dictionary hits are translated without an API) |
| `//at del <word>` | Remove a dictionary entry |
| `//at dict` | List the dictionary |
| `//at mode <types...>` | Choose which chat types to translate (e.g. `//at mode party ls tell`). Types: say shout yell tell party ls unity echo |
| `//at mode status` | Show which chat types are translated |
| `//at block <name>` / `//at unblock <name>` | Do not translate messages from this player / undo (`//at block` alone lists them) |
| `//at word add <word>` / `//at word del <word>` | Do not translate messages containing this word (NG words) |
| `//at slang add <abbreviation> <meaning>` / `//at slang del <abbreviation>` | Add / remove a slang entry (e.g. `//at slang add omw on my way`) |
| `//at slang list` / `//at slang reload` | List the slang dictionary / reload it after editing `data/slang.xml` |
| `//at typo add <typo> <correct spelling>` | Add an entry to the typo correction table (`del` / `list` work the same; the table is `data/typo.xml`) |
| `//at hud` | Toggle the small on-screen translation window (`//at hud reset` resets its position) |
| `//at toggle` | Turn translation on / off |

### How it works

```
Game (Lua)                                    Translator helper (PowerShell, no window)
  Receives a chat line
  Shows it at once if found in the dictionary/cache
  Otherwise writes data/queue/<id>.req  ───▶  Picks up the request and calls the API
  Checks for a result every 0.1 s       ◀───  Writes data/queue/<id>.res
  Shows the result in the chat log
```

- The translator helper (`helper/at_helper.ps1`) is started without a window through `helper/start_helper.vbs` when AutoTranslator loads.
- The helper exits by itself when AutoTranslator is unloaded or reloaded, or 30 seconds after the game exits.
- Area names come from Windower's resources (`res/zones.lua`, `res/regions.lua`); auto-translate phrases come from `res/auto_translates.lua`, `res/items.lua`, and others.
- For English → Japanese, the area-name table is registered automatically as a **DeepL glossary**.
  - The DeepL free plan allows only one glossary, so Japanese → English does not use a glossary; place names are replaced with their English names before sending.
  - The glossary registration is stored in `data/deepl_glossary.txt` (it is re-registered automatically when your API key changes).
- The helper's activity is logged to `data/queue/helper.log` (API keys are never logged).

### Notes

- **API keys are stored in plain text in `filler.xml`.** `filler.xml` is excluded by `.gitignore`. Never upload it to GitHub or anywhere else.
- Usage fees and character limits follow each translation service's terms.
- Windower's Lua (5.1) has no ffi, so the native-DLL translation in `src/` and `libs/native_bridge.lua` is not used (the translator helper is used instead).
- The OpenAI / Claude model names are set in `helper/at_helper.ps1`. Update them if a model is retired.

### License

Released under the MIT License. See [LICENSE](LICENSE) for details.
