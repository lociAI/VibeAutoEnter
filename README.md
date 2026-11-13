# 🪄 VibeAutoEnter for macOS (v1.2)

A native macOS app designed specifically for **vibe coders** who use AI CLI tools (Claude Code, Codex, Aider, Antigravity CLI) and AI IDEs (Cursor, Windsurf, VS Code, Claude Desktop, ChatGPT, Zed, Xcode).

---

## ✨ What's New in v1.2: Multi-Terminal Auto-Swap & Patrol

### 🔄 Multi-Terminal Auto-Swap & Patrol
- **Automatic Window Rotation**:
  - If you have more than one Terminal window open (e.g. one for frontend dev, one for backend agent, one for tests), the app automatically cycles focus between them every few seconds (default: `3.0s`, customizable from `1.5s` to `10.0s`).
  - Swapping brings each window forward so you can watch your agents work in real-time.
- **Instant Prompt Interception**:
  - When **any** terminal window presents a prompt (`[y/N]`, `1. Yes, accept this change`, `Pick an option [1-3]:`), the app **immediately jumps straight to that window**, types `"y"` or presses <kbd>Return</kbd>, and continues on without delay.
- **Smart De-duplication**:
  - Remembers which window and prompt was already answered so it never gets stuck in a loop.

---

## 🚀 Controls & Settings

Inside the **VibeAutoEnter** window or menu bar popover:
1. **Auto-Swap & Patrol Open Terminals**:
   - Toggle on/off auto-rotation.
   - Adjust the **Swap & check every** slider (1.5s – 10.0s).
2. **Auto-Accept Prompts**:
   - Auto-types `"y"` + Return for `[y/N]`, `(y/n)`, `[yes/no]`, `proceed?`.
3. **Auto-Pick Numbers**:
   - Auto-presses Return for `> 1. Yes, accept`, `Choice [1]:`, `[1-3]:`.
4. **AI Completion Alerts**:
   - Chimes and sends notifications when background processes finish.

---

## 🖥️ Launching

- Double-click the **VibeAutoEnter** shortcut on your **Desktop**.
- Or run `open -a ~/Applications/VibeAutoEnter.app`.
