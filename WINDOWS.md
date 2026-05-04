# Installing on Windows

You will need about 10 minutes and a Windows 10 or 11 computer.

---

## Step 1 — Install Git for Windows

Git for Windows gives you the tools this script needs to run.

1. Go to **https://git-scm.com/download/win** and click the download button.
2. Run the installer. Click **Next** on every screen — the defaults are fine.
3. When it finishes, close the installer.

To check it worked: press the **Windows key**, type `cmd`, press **Enter**. In the black window that opens, type `git --version` and press **Enter**. You should see something like `git version 2.x.x`.

---

## Step 2 — Install jq

jq is a small tool that reads JSON data. The script needs it to understand the information Claude Code sends.

1. Go to **https://jqlang.org/download/** and click **jq 1.7.1 — jq-windows-amd64.exe** (or whatever the latest version is).
2. Save the file somewhere easy to find, like your Downloads folder.
3. Rename the downloaded file to exactly **`jq.exe`** (right-click the file, choose **Rename**).
4. Move `jq.exe` to `C:\Windows\System32\` — this is a special folder that makes `jq` available everywhere.
   - Open File Explorer, navigate to `C:\Windows\System32\`, and drag `jq.exe` in. If Windows asks for permission, click **Yes**.

To check it worked: in the black cmd window, type `jq --version` and press **Enter**. You should see `jq-1.7.1` or similar.

---

## Step 3 — Download this repo

1. Press the **Windows key**, type `cmd`, press **Enter** to open the black command window again.
2. Type this exactly and press **Enter**:

```
git clone https://github.com/Clarity-EngineAI/Claude-Code-Status-Clarity.git "%USERPROFILE%\Claude-Code-Status-Clarity"
```

This copies all the script files into a folder called `Claude-Code-Status-Clarity` inside your user folder (for example `C:\Users\Alex\Claude-Code-Status-Clarity`).

---

## Step 4 — Find your settings file

Claude Code has a settings file where you tell it to use this script.

1. Press **Windows key + R**, type `%USERPROFILE%\.claude` and press **Enter**. File Explorer will open that folder.
2. Look for a file called `settings.json`.
   - If it exists, right-click it and open it with **Notepad**.
   - If it does not exist, right-click an empty area in the folder, choose **New > Text Document**, name it `settings.json`, then open it in Notepad.

---

## Step 5 — Edit the settings file

In Notepad, you need to add a `statusLine` entry. Replace `Alex` with your actual Windows username.

**If the file is empty**, paste in this entire block:

```json
{
  "statusLine": {
    "type": "command",
    "command": "C:\\Users\\Alex\\Claude-Code-Status-Clarity\\statusline.cmd"
  }
}
```

**If the file already has stuff in it**, find the last `}` on its own line, add a comma after the line above it, then add the `statusLine` block. Ask a grown-up for help if you are not sure — JSON files are picky about commas.

Save the file (**Ctrl + S**) and close Notepad.

---

## Step 6 — Restart Claude Code

Close Claude Code completely and open it again. The statusline should now appear at the bottom of every response, showing context, cost, and rate limits.

---

## Troubleshooting

**Nothing shows up**

Open the cmd window and run:

```
bash "%USERPROFILE%\Claude-Code-Status-Clarity\statusline.sh"
```

If you see an error about `jq not found`, go back to Step 2.
If you see an error about `bash not found`, go back to Step 1.

**The statusline shows boxes or question marks instead of icons**

Your terminal does not support the special characters. Add `CLAUDE_STATUSLINE_ASCII=1` before the command in settings.json:

```json
"command": "set CLAUDE_STATUSLINE_ASCII=1 && C:\\Users\\Alex\\Claude-Code-Status-Clarity\\statusline.cmd"
```

**I am not sure what my username is**

In the black cmd window, type `echo %USERNAME%` and press **Enter**.
