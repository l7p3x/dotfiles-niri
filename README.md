 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/README.md b/README.md
index 5625332d26b8d5f261383503404ead7d30b72d53..6b89ce4d6d742159f59de25a48a9133269bfa78a 100644
--- a/README.md
+++ b/README.md
@@ -1 +1,62 @@
-# dotfile-niri
+# 󰣇 dotfile-niri
+
+My personal **Niri dotfiles** setup — clean, comfy, and easy to copy.
+
+## 󰋩 Quick look
+
+A simple desktop setup with wallpapers, screenshots, and a ready install script.
+
+| Desktop | Terminal |
+|---|---|
+| ![Desktop](screenshots/desktop.png) | ![Terminal](screenshots/terminal.png) |
+
+| Fuzzel | Alt desktop |
+|---|---|
+| ![Fuzzel](screenshots/fuzzel.png) | ![Desktop 2](screenshots/desktop2.png) |
+
+󰈹 **Video preview:** [`screenshots/preview.mp4`](screenshots/preview.mp4)
+
+## 󰙅 What’s inside
+
+- `install.sh` — quick install/setup script
+- `screenshots/` — demo images + video
+- `Wallpaper/` — wallpapers for this setup
+
+## 󰅐 Install
+
+```bash
+chmod +x install.sh
+./install.sh
+```
+
+## 󰸉 Included wallpapers
+
+- Noctis
+- Tux
+- Girl
+- Cyberpunk
+- Minimalistic
+- Forest
+- Abstract
+- QcqKfdZ
+- Fish
+
+## 󰒓 Make it yours
+
+Feel free to tweak it however you want:
+
+- swap wallpapers from `Wallpaper/`
+- replace screenshots with your own style
+- customize `install.sh` for your flow
+
+## 󰀼 Contributing
+
+PRs are welcome.
+
+1. Fork this repo
+2. Create your feature branch
+3. Open a pull request
+
+## 󰿃 License
+
+No license file yet — add one if you want (MIT is a good default).
 
EOF
)
