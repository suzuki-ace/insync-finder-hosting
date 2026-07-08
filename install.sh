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
RAW="https://raw.githubusercontent.com/suzuki-ace/insync-finder-hosting/main/src"

INSTALL_BIN="$HOME/Library/Application Support/InsyncFinder"
HOST_PATH="$INSTALL_BIN/insync-find-host.py"
URL_PATH="$INSTALL_BIN/insync-url.py"

echo "Insync Finder の裏方を設置します..."

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

# --- 3) クイックアクション（ローカル→Drive URL）を ~/Library/Services に自動生成 ---
WF="$HOME/Library/Services/Drive URLをコピー.workflow"
mkdir -p "$WF/Contents"

cat > "$WF/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Drive URLをコピー</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.item</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

cat > "$WF/Contents/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>for f in "$@"; do
  /usr/bin/python3 "$HOME/Library/Application Support/InsyncFinder/insync-url.py" "$f"
done</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>A1B2C3D4-0001-4000-8000-000000000001</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>A1B2C3D4-0001-4000-8000-000000000002</string>
				<key>UUID</key>
				<string>A1B2C3D4-0001-4000-8000-000000000003</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>449.000000:316.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>11</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceApplicationPath</key>
		<string>/System/Library/CoreServices/Finder.app</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

echo "設置: $WF"
# サービス一覧を再読込（メニューへの反映を促す。失敗しても続行）
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true

# --- 4) python3 の確認 -----------------------------------------------------------
if ! /usr/bin/env python3 --version >/dev/null 2>&1; then
  echo "注意: python3 が見当たりません。ターミナルで  xcode-select --install  を実行してください。" >&2
fi

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
