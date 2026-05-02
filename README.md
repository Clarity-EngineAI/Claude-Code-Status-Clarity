# Claude Code Status Clarity

Know exactly where your Claude Code session stands. At a glance: context fill, burn rate, cost, rate limits with time-to-reset, MCP health, and recent tool calls — displayed as a two-line statusline on every response.

```
◇  Claude Sonnet 4.6  │  ████████░░ 78%  │  $0.42  │  3m12s  │  5h↑23%
⌿main*  │  +14/-3  │  my-project  │  Fix auth bug  │  ⊕3
```

The context bar shifts from green to yellow and then red as you approach your session limit. The model name is colour-coded by tier:
Haiku in faint, Sonnet in amber, Opus in purple so you always know which model you're using and paying for. Rate limits show as live percentages with reset countdowns so you can pace yourself instead of hitting a wall.

It's a pure bash script with no runtime dependencies beyond `jq`. Drop it in, point Claude Code at it, and it works.

## Requirements

- **bash** 3.2 or later (macOS default bash works)
- **jq** 1.6 or later — `brew install jq` / `apt install jq`
- **awk** — standard on macOS and Linux
- **git** — optional, useful for live branch display

## Installation

**1. Clone the repo**

```bash
git clone https://github.com/Clarity-EngineAI/Claude-Code-Status-Clarity.git ~/Claude-Code-Status-Clarity
chmod +x ~/Claude-Code-Status-Clarity/statusline.sh
```

**2. Add to Claude Code settings**

Edit `~/.claude/settings.json` (create it if it does not exist):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/Users/yourname/Claude-Code-Status-Clarity/statusline.sh\""
  }
}
```

Replace the path with wherever you cloned the repo. Restart Claude Code and the statusline appears immediately.

## What it shows

**Line 1** — model and cost
- State glyph: `◇` idle · `◆` streaming (ASCII: `< >` / `<>`)
- Model name, colour-coded by tier: Haiku (faint) · Sonnet (amber) · Opus (purple)
- `fast` badge when fast mode is active
- Context bar: 10-block gradient fill with percentage
- Session cost in USD
- Wall-clock duration
- Rate limits when available: `5h↑23%` · `7d↑11%`

**Line 2** — workspace
- Git branch with `*` dirty indicator and `⌿` worktree prefix
- Lines changed: `+14/-3`
- Working directory name
- Session name (when set via `--name` or `/rename`)
- MCP server count: `⊕3`

## Configuration

All options are environment variables. Set them in the `command` string in `settings.json`.

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_STATUSLINE_THEME` | `warm` | Colour theme: `warm` · `cool` · `mono` · `terminal-classic` · `nerdfont-powerline` |
| `CLAUDE_STATUSLINE_ASCII` | `0` | `1` — force ASCII glyphs, no Unicode |
| `CLAUDE_STATUSLINE_NERDFONT` | `0` | `1` — enable Nerd Font glyphs |
| `CLAUDE_STATUSLINE_POWERLINE` | `0` | `1` — enable Powerline separators |
| `CLAUDE_STATUSLINE_FORECAST` | `0` | `1` — show burn rate and velocity forecast |
| `CLAUDE_STATUSLINE_TRACE` | `0` | `1` — show third line with MCP tool trace |
| `CLAUDE_STATUSLINE_NO_GIT` | `0` | `1` — suppress live git branch lookups |
| `CLAUDE_STATUSLINE_DEBUG` | `0` | `1` — write debug log to `/tmp/claude-statusline.log` |

Example with options:

```json
{
  "statusLine": {
    "type": "command",
    "command": "CLAUDE_STATUSLINE_THEME=cool CLAUDE_STATUSLINE_NERDFONT=1 bash \"/Users/yourname/Claude-Code-Status-Clarity/statusline.sh\""
  }
}
```

## Testing

```bash
bash examples/test-mock.sh all        # run all 13 fixture tests
bash examples/test-mock.sh visual     # render all fixtures in your terminal
bash examples/test-mock.sh 01-basic   # run a single fixture
```

## Repository layout

```
statusline.sh          main entry point — reads JSON from Claude Code, prints 2 lines
lib/
  theme.sh             colour presets and symbol sets
  history.sh           per-session cost/context history (used by forecast)
  forecast.sh          burn rate and velocity calculations
examples/
  test-mock.sh         test harness
  fixtures/            JSON payloads + expected output for each scenario

Build by Clarity Engine
```
