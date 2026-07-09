#!/bin/bash
# Insync Finder - 各ユーザーのMacに「裏方」を設置するスクリプト（管理者権限は不要）
#   ・Drive→ローカル 用のネイティブホスト（Chrome拡張が呼ぶ）
#   ・ローカル→Drive 用の逆引きスクリプト＋クイックアクション（Finderの右クリックが呼ぶ）
#
# Chrome拡張本体は Google Workspace（管理コンソール）から強制インストールされる想定。
# このスクリプトは、拡張が動くために各Macに必要な「裏方」だけを設置する。
#
# 実行（どちらでも可）:
#   curl -fsSL https://raw.githubusercontent.com/suzuki-ace/insync-finder-hosting/main/install.sh | bash
#   bash install.sh
set -e

EXT_ID="nmmhggggollcnpglgdmjojnmohgkifhn"   # 拡張の固定ID（自己ホストcrx／unpackedとも共通）
HOST_NAME="com.ujike.insyncfind"
# 取得元は配布向けCDNのjsDelivr（GitHub rawはレート制限=429を踏みやすいため）
RAW="https://cdn.jsdelivr.net/gh/suzuki-ace/insync-finder-hosting@main/src"

INSTALL_BIN="$HOME/Library/Application Support/InsyncFinder"
HOST_PATH="$INSTALL_BIN/insync-find-host.py"
URL_PATH="$INSTALL_BIN/insync-url.py"

echo "Insync Finder の裏方を設置します..."

# --- 0) python3（Command Line Tools）の確認 -------------------------------------
# 両スクリプトは /usr/bin/python3（CLT同梱・純正）で動く。未導入なら先にCLTを入れる。
if ! /usr/bin/python3 -V >/dev/null 2>&1; then
  echo "python3 が見つかりません。コマンドラインツール（CLT）をインストールします..." >&2
  xcode-select --install >/dev/null 2>&1 || true
  echo "" >&2
  echo "→ 画面に出たダイアログで『インストール』を押してください（管理者権限は不要・数分）。" >&2
  echo "→ 完了したら、この install.sh をもう一度実行してください。" >&2
  exit 1
fi

# --- 1) 裏方2本をGitHubからダウンロードして設置 ---------------------------------
mkdir -p "$INSTALL_BIN"
dl() {  # dl <url> <dest>
  if ! curl -fsSL "$1" -o "$2"; then
    echo "ダウンロード失敗: $1" >&2
    echo "  ネット接続とURLを確認してください（社内プロキシがある場合は要確認）。" >&2
    exit 1
  fi
}
dl "$RAW/native-host/insync-find-host.py" "$HOST_PATH"
dl "$RAW/local-to-drive/insync-url.py"    "$URL_PATH"
chmod +x "$HOST_PATH" "$URL_PATH"
echo "設置: $HOST_PATH"
echo "設置: $URL_PATH"

# --- 2) Chrome系ブラウザのネイティブホスト・マニフェストを設置 -------------------
TARGETS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts"
  "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
)
installed=0
for dir in "${TARGETS[@]}"; do
  if [ -d "$(dirname "$dir")" ]; then
    mkdir -p "$dir"
    cat > "$dir/$HOST_NAME.json" <<JSON
{
  "name": "$HOST_NAME",
  "description": "Insync Finder native host",
  "path": "$HOST_PATH",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
JSON
    echo "設置: $dir/$HOST_NAME.json"
    installed=1
  fi
done
[ "$installed" -eq 0 ] && { echo "Chrome系ブラウザが見つかりません。Chromeを一度起動して再実行してください。" >&2; exit 1; }

# --- 3) クイックアクション（ローカル→Drive URL）を ~/Library/Services に設置 -------
# 手書きの .workflow は Finder への紐付け情報が不足し右クリックに出ないため、
# Automatorで作成・動作確認済みのバンドル2ファイルをGitHubから取得して組み立てる。
WF="$HOME/Library/Services/Drive URLをコピー.workflow"
mkdir -p "$WF/Contents"
dl "$RAW/quickaction/Info.plist"     "$WF/Contents/Info.plist"
dl "$RAW/quickaction/document.wflow" "$WF/Contents/document.wflow"
echo "設置: $WF"

# Finder右クリック表示を有効化（NSServicesStatus。手動配置では自動で入らないため明示的に）
# キーは "(null) - <メニュー名> - runWorkflowAsService"。defaultsが (null) を解釈できないので PlistBuddy を使う。
PBS_PLIST="$HOME/Library/Preferences/pbs.plist"
SVC_KEY=":NSServicesStatus:(null) - Drive URLをコピー - runWorkflowAsService"
defaults read pbs >/dev/null 2>&1 || true   # cfprefsd の状態をディスクへ同期
/usr/libexec/PlistBuddy -c "Delete '$SVC_KEY'" "$PBS_PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy \
  -c "Add '$SVC_KEY' dict" \
  -c "Add '$SVC_KEY:presentation_modes' dict" \
  -c "Add '$SVC_KEY:presentation_modes:ContextMenu' bool true" \
  -c "Add '$SVC_KEY:presentation_modes:ServicesMenu' bool true" \
  -c "Add '$SVC_KEY:presentation_modes:FinderPreview' bool true" \
  "$PBS_PLIST" >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true

# サービス一覧を再読込し、Finderを再起動して反映（失敗しても続行）
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

cat <<'DONE'

裏方の設置が完了しました。
  ・ネイティブホスト     : ~/Library/Application Support/InsyncFinder/insync-find-host.py
  ・逆引きスクリプト     : ~/Library/Application Support/InsyncFinder/insync-url.py
  ・クイックアクション   : ~/Library/Services/Drive URLをコピー.workflow

次にやること:
  1. Chrome を ⌘Q で完全終了 → 再起動（ネイティブホストの反映のため）
  2. 拡張「Insync Finder」は管理コンソールから自動配布されます。
     （テスト時は chrome://extensions でデベロッパーモード → src/insync-finder を読み込み）
  3. 使い方:
     ・Drive→ローカル : Driveでファイルを開き、ツールバーの Insync Finder アイコンをクリック
     ・ローカル→Drive : Finderでファイルを右クリック → クイックアクション →「Drive URLをコピー」
DONE
