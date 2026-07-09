# Insync Finder（配布用ホスティングリポジトリ）

Google Drive とローカル（Insync 同期先）を双方向でつなぐ 2 機能を、社内の各 Mac に配布するためのリポジトリです。

- **Drive → ローカル**：Chrome 拡張「Insync Finder」＋ネイティブホスト。Drive で開いたファイルを Mac の既定アプリで開く／Finder で表示する。
- **ローカル → Drive**：逆引きスクリプト＋クイックアクション。Finder でファイルを右クリック →「Drive URLをコピー」で Drive URL を取得する。

拡張は **Google Workspace（管理コンソール）から強制インストール**、裏方（ネイティブホスト・逆引き・クイックアクション）は **各 Mac で `install.sh` を 1 回実行**して設置します。

- 拡張ID：`nmmhggggollcnpglgdmjojnmohgkifhn`（自己ホスト crx／unpacked とも共通）
- 配布 crx：`insync-finder.crx` ／ 更新マニフェスト：`update.xml`

---

## 仕組みと安全性

すべての処理は各ユーザーの Mac 内で完結します。外部サーバーへの通信や第三者へのデータ送信は行いません。

- 拡張は同じ Mac 内のネイティブホストとだけやり取りします（Chrome の Native Messaging）。
- 裏方は Insync の同期台帳（SQLite）を **読み取り専用**（一時コピーを参照）で引き、ローカルのパスを割り出して `open` するだけ。台帳や元ファイルは書き換えません。
- 拡張の権限は最小限：`nativeMessaging`・`tabs`（今開いている Drive タブの URL 取得）・`contextMenus`。ページ内容や他タブは読みません。
- 台帳のルートは各 Mac 自身の絶対パス（ユーザー名込み）を保持するため、ユーザー名の違いでパスがズレることはありません。

---

## 各 Mac への導入（裏方の設置）

拡張が管理コンソールから入っていても、裏方を入れないと動きません。各 Mac で次を 1 回実行します（管理者権限は不要）。

```
curl -fsSL https://cdn.jsdelivr.net/gh/suzuki-ace/insync-finder-hosting@v1.2.1/install.sh | bash
```

これで次が設置されます。

- ネイティブホスト：`~/Library/Application Support/InsyncFinder/insync-find-host.py`
- 逆引きスクリプト：`~/Library/Application Support/InsyncFinder/insync-url.py`
- クイックアクション：`~/Library/Services/Drive URLをコピー.workflow`（Automator 手作業は不要）
- ネイティブホスト・マニフェスト：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.ujike.insyncfind.json`

実行後、**Chrome を ⌘Q で完全終了 → 再起動**してください。

### 前提
- macOS ＋ Google Chrome
- Insync 導入・同期済み（`~/Library/Application Support/Insync/data/gd-*.db` が存在）
- python3（無ければ `xcode-select --install`）
- 全社で Insync のバージョンをそろえること（台帳の構造が変わると動かなくなるため）

---

## 使い方

- **Drive のファイルをローカルで開く**：Drive で対象ファイルを開いた状態（URL が `/d/…`）で、ツールバーの Insync Finder アイコンをクリック → 既定アプリで開く。フォルダや位置確認はページ上で右クリック →「Finderで表示」。
- **ローカルのファイルの Drive URL を取る**：Finder でファイルを右クリック → クイックアクション →「Drive URLをコピー」。URL がクリップボードに入り通知が出ます。
- アイコンのバッジ：✓＝成功、!＝未同期/見つからない、×＝裏方に届かない、?＝URL を拾えない。

---

## 管理者向け：Workspace での強制インストール

Google 管理コンソール →「デバイス」→「Chrome」→「アプリと拡張機能」→ 対象の組織部門（OU）を選択。

1. 右下「＋」→「URL で追加」
2. **拡張機能 ID**：`nmmhggggollcnpglgdmjojnmohgkifhn`
3. **更新 URL**：`https://raw.githubusercontent.com/suzuki-ace/insync-finder-hosting/main/update.xml`
4. インストールポリシーを「**強制インストール**」に設定

まず小さなテスト OU で確認してから全体へ広げてください。裏方（`install.sh` の実行）は拡張配布では入らないため、MDM で `install.sh` をユーザーコンテキスト実行するか、各ユーザーに上記コマンドを実施してもらいます。

---

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| バッジが **×** | 裏方が未設置、または python3 が無い。`install.sh` を実行し、`xcode-select --install` を確認。Chrome を ⌘Q で再起動。 |
| バッジが **!** | そのファイルがローカル未同期、または別 Google アカウント。Insync の同期対象か確認。 |
| バッジが **?** | 押したタブが特定ファイルでなくフォルダ一覧など。ファイルを開いて（URL が `/d/…`）から押す。 |
| 右クリックに「Drive URLをコピー」が出ない | `pbs -flush` 済みでも出ない場合、再ログイン、またはシステム設定 →「一般」→「ログイン項目と機能拡張」→「Finder 機能拡張」で有効化。 |
| 逆引きで「見つかりません」 | Insync 同期外、または未ダウンロード（部分同期）。 |
| ある日突然 ! や × が続く | Insync のバージョンアップで台帳構造が変わった可能性。保守担当に連絡。 |

---

## リポジトリ構成

```
insync-finder-hosting/
├── insync-finder.crx        配布用パック済み拡張（強制インストールの実体）
├── update.xml               強制インストール用マニフェスト
├── install.sh               各Macの裏方を設置（curl | bash）
├── src/
│   ├── insync-finder/       拡張ソース（テスト時に unpacked 読み込み）
│   ├── native-host/         ネイティブホスト（install.sh がDL・設置）
│   └── local-to-drive/      逆引きスクリプト（install.sh がDL・設置）
└── README.md
```

---

## 保守：拡張を更新するとき

1. `src/insync-finder/manifest.json` の `version` を上げる。
2. 同じ署名鍵で再パック（ID を固定するため **同一 `insync-finder.pem` を使う**）：
   ```
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
     --pack-extension="$PWD/src/insync-finder" \
     --pack-extension-key="$PWD/insync-finder.pem"
   mv src/insync-finder.crx ./insync-finder.crx
   ```
3. `update.xml` の `version` を manifest と一致させる。
4. commit → push。管理下の Chrome が更新 URL を見て自動更新します。

> **重要**：`insync-finder.pem`（署名鍵）は**このリポジトリにコミットしない**（`.gitignore` 済み）。紛失すると同一 ID で再パックできず、全 Mac で拡張を入れ直しになります。保守担当が別途安全に保管してください。
