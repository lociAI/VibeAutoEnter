# 🚀 VibeAutoEnter $1 Paid Release & Storefront Guide

This guide walks you through selling **VibeAutoEnter** as a **$1.00 paid download (no free trial)** on digital merchant marketplaces (**Gumroad**, **Lemon Squeezy**, or **Polar**).

---

## 💎 1. Monetization Model

- **Price**: **$1.00** (One-time paid download)
- **Free Trial**: None (paid upfront before download)
- **In-App Gating**: Removed — buyers receive the full unlocked app immediately upon download:
  - Single & Multi-Terminal Auto-Swap & Patrol
  - Auto-Accept (`[y/N]`, `(y/n)`, `proceed`) & Auto-Pick Numbers (`[1-3]`, choice)
  - GUI IDE Auto-Enter (Cursor, Claude Desktop, Windsurf)
  - Turbo Prompt Interception (< 1.0s delay)
  - AI Completion Chimes & System Alerts

> **Why Direct Distribution instead of the Mac App Store?**
> VibeAutoEnter monitors external apps (Terminal, Cursor, Windsurf, Claude Desktop) and injects keystrokes using Accessibility (`AXUIElement` / `CGEvent`) and AppleEvents. Mac App Store apps must be App Sandboxed, which blocks cross-app Accessibility automation.

---

## 🛠️ 2. Marketplace Setup (Step-by-Step)

### Option A: Gumroad (Fastest for $1 Paid Downloads)
1. Go to [gumroad.com](https://gumroad.com) and create a product named `VibeAutoEnter`.
2. Set the price to **$1.00** (one-time purchase, no free trial).
3. In the **Content** tab, upload `dist/VibeAutoEnter-1.2.dmg` (built with `./package_release.sh`).
4. Publish and share your Gumroad link.

### Option B: Lemon Squeezy (Merchant of Record)
1. Sign up at [lemonsqueezy.com](https://lemonsqueezy.com) and create your store.
2. Create a product named `VibeAutoEnter` priced at **$1.00** (One-time payment).
3. Under **Files**, upload `dist/VibeAutoEnter-1.2.dmg` (no license key required).
4. Publish and share your checkout URL.

---

## 📦 3. Building the Production DMG Package

To build and package the DMG for uploading to your marketplace:

```bash
cd /Users/mac101/Developer/VibeAutoEnter
./package_release.sh
```

This generates:
- `dist/VibeAutoEnter-1.2.dmg` (Universal binary for Apple Silicon & Intel)
- `dist/VibeAutoEnter-1.2.dmg.sha256`

---

## 🔏 4. Apple Developer ID & Notarization (Recommended for Gatekeeper)

To prevent macOS from displaying *"VibeAutoEnter cannot be opened because it is from an unidentified developer"*:

1. **Apple Developer Account**: Requires an Apple Developer membership ($99/year).
2. **Sign with Developer ID**:
   ```bash
   codesign --force --options runtime --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
       --entitlements VibeAutoEnter/VibeAutoEnter.entitlements \
       build/VibeAutoEnter.app
   ```
3. **Notarize the DMG**:
   ```bash
   xcrun notarytool submit dist/VibeAutoEnter-1.2.dmg \
       --apple-id "your@appleid.com" \
       --team-id "TEAM_ID" \
       --password "app-specific-password" \
       --wait
   ```
4. **Staple the Ticket**:
   ```bash
   xcrun stapler staple dist/VibeAutoEnter-1.2.dmg
   ```

*(Before notarization, buyers can right-click the app -> Open, or run `xattr -cr /Applications/VibeAutoEnter.app`).*

---

## 📝 5. Storefront Copy

### **Headline**
> **Never wait around to press Enter again.** Hands-free prompt automation for AI vibe coders — **$1**.

### **Short Tagline**
> Built for developers running Claude Code, Codex, Aider, Antigravity CLI, Cursor, Windsurf, and terminal agents in parallel.

### **Product Description**
```markdown
Are you tired of staring at your terminal waiting for AI agents to ask:
- `Allow command? [y/N]`
- `Proceed with changes? (y/n)`
- `Pick an option [1-3]:`

**VibeAutoEnter** patrols your open terminal windows and IDEs in the background, auto-intercepting confirmation prompts the instant they appear so your agents can finish building while you grab coffee.

### ⚡ Included for $1 (One-Time Purchase):
- 🔄 **Multi-Terminal Auto-Swap & Patrol**: Cycles through and monitors multiple terminal windows in real time.
- 🎯 **Auto-Pick Menus & Options**: Automatically selects default and numbered menu options [1-3].
- 💻 **IDE Auto-Enter**: Seamlessly presses Enter for suggested completions in Cursor, Claude Desktop, and Windsurf.
- ⚡ **Turbo Speed Control**: Sub-second prompt execution (< 1.0s).
- 🔔 **Smart AI Completion Alerts**: Audio chimes and banner notifications when background tasks complete.
- 🛡️ **100% Local & Offline**: No cloud telemetry, no API keys required, works completely on your Mac.

### Requirements:
- macOS 14.0 (Sonoma) or newer (Apple Silicon & Intel supported)
- Accessibility permission enabled in System Settings
```
