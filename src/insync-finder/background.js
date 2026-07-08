// Insync Finder - background service worker
const HOST = "com.ujike.insyncfind";

function badge(text, color) {
  chrome.action.setBadgeBackgroundColor({ color: color || "#999999" });
  chrome.action.setBadgeText({ text: text || "" });
  if (text) setTimeout(() => chrome.action.setBadgeText({ text: "" }), 4000);
}

function send(url, mode) {
  if (!url) { badge("?", "#e11d48"); return; }
  chrome.runtime.sendNativeMessage(HOST, { url, mode: mode || "open" }, (resp) => {
    if (chrome.runtime.lastError) {
      badge("×", "#e11d48");
      console.error("native host error:", chrome.runtime.lastError.message);
      return;
    }
    if (resp && resp.ok) {
      badge("✓", "#16a34a");
    } else {
      badge("!", "#e11d48");
      console.warn("insync-find:", resp && (resp.error || resp.path));
    }
  });
}

// tab.url が空でも、アクティブタブを取り直してURLを確定する
async function resolveActiveUrl(tab) {
  if (tab && tab.url) return tab.url;
  try {
    const [t] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (t && t.url) return t.url;
    if (t && t.id != null) {
      const info = await chrome.tabs.get(t.id);
      if (info && info.url) return info.url;
    }
  } catch (e) {
    console.error("tab query failed:", e);
  }
  return "";
}

// ツールバーのアイコン → 既定アプリで開く
chrome.action.onClicked.addListener(async (tab) => {
  const url = await resolveActiveUrl(tab);
  console.log("action clicked, url =", url);
  send(url, "open");
});

// 右クリックメニュー：既定アプリで開く / Finderで表示 の2つ
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "insync-open",
      title: "既定のアプリで開く",
      contexts: ["page", "link"]
    });
    chrome.contextMenus.create({
      id: "insync-reveal",
      title: "Finderで表示",
      contexts: ["page", "link"]
    });
  });
});
chrome.contextMenus.onClicked.addListener((info, tab) => {
  const url = info.linkUrl || info.pageUrl || (tab && tab.url);
  send(url, info.menuItemId === "insync-reveal" ? "reveal" : "open");
});
