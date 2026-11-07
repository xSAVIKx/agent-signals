# The login copy for scenarios. Source this file after scenarios/lib.sh;
# do not run it. It is not part of the agent kit: the kit never copies a
# login file.
#
# copy_login reads REAL_HOME and SCN_HOME, which sandbox_start sets.

# shellcheck shell=sh

# copy_login AGENT: copy the current login of AGENT from REAL_HOME into the
# throwaway HOME. Returns 1 when there is no login, or when the login is
# too near its expiry: a refresh in the copy could make the original fail.
copy_login() {
  case $1 in
    claude)
      f=$REAL_HOME/.claude/.credentials.json
      [ -f "$f" ] || return 1
      python3 - "$f" <<'EOF' || return 1
import json, sys, time
d = json.load(open(sys.argv[1])).get("claudeAiOauth", {})
sys.exit(0 if d.get("expiresAt", 0) / 1000 - time.time() > 1800 else 1)
EOF
      mkdir -p "$SCN_HOME/.claude"
      cp "$f" "$SCN_HOME/.claude/.credentials.json"
      # With CLAUDE_CONFIG_DIR (scenarios/lib.sh), Claude Code reads this
      # file in the config folder. The copy in HOME is for a scenario that
      # starts the agent with no such variable.
      printf '{"hasCompletedOnboarding":true,"theme":"dark"}\n' >"$SCN_HOME/.claude.json"
      cp "$SCN_HOME/.claude.json" "$SCN_HOME/.claude/.claude.json"
      ;;
    codex)
      f=$REAL_HOME/.codex/auth.json
      [ -f "$f" ] || return 1
      python3 - "$f" <<'EOF' || return 1
import base64, datetime, json, sys, time
d = json.load(open(sys.argv[1]))
# Codex refreshes a login that is older than about 8 days, and when the
# access token has expired. Either refresh in the copy could make the
# original login fail, so refuse both cases.
t = datetime.datetime.fromisoformat(d["last_refresh"].replace("Z", "+00:00"))
age = datetime.datetime.now(datetime.timezone.utc) - t
p = d["tokens"]["access_token"].split(".")[1]
exp = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4))).get("exp", 0)
sys.exit(0 if age.days < 7 and exp - time.time() > 7200 else 1)
EOF
      mkdir -p "$SCN_HOME/.codex"
      cp "$f" "$SCN_HOME/.codex/auth.json"
      ;;
    agy)
      f=$REAL_HOME/.gemini/antigravity-cli/antigravity-oauth-token
      [ -f "$f" ] || return 1
      mkdir -p "$SCN_HOME/.gemini/antigravity-cli"
      cp "$f" "$SCN_HOME/.gemini/antigravity-cli/"
      # The onboarding state, so that the first-run wizard does not open.
      for s in jetski_state.pbtxt installation_id; do
        [ -f "$REAL_HOME/.gemini/antigravity-cli/$s" ] &&
          cp "$REAL_HOME/.gemini/antigravity-cli/$s" "$SCN_HOME/.gemini/antigravity-cli/"
      done
      ;;
    cursor)
      # The Cursor CLI takes CURSOR_API_KEY from the environment.
      [ -n "${CURSOR_API_KEY:-}" ] || return 1
      ;;
    *) return 1 ;;
  esac
}
