#!/usr/bin/env bash
# uninstall.sh — undo install.sh, using the change log it wrote.
#
# Default: put the configs back. Symlinks are removed, whatever was displaced is
# restored (a real file from its .bak, an old symlink recreated), files install.sh
# created are taken away, and the cli-tools checkout plus every binary built from
# it are deleted — whatever toolchain built them.
#
# --full also removes what install.sh *added* to the machine: the Homebrew
# packages this repo installed (as recorded, so pre-existing ones are left),
# mp3book, and the vim plugins. Versions are reported so anything upgraded can
# be put back deliberately.
#
# Homebrew itself, and any language runtime or toolchain, are never uninstalled,
# even with --full. Other formulae link against brew's python, and removing
# go/node/php breaks much more than this repo ever set up.
#
# Usage: ./uninstall.sh [--dry-run] [--full] [--force]
#   --dry-run  show what would happen
#   --full     also remove added packages (see above)
#   --force    proceed where the current state isn't what install.sh left
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
MANIFEST="$STATE_DIR/install.json"
STAMP="$(date +%Y%m%d%H%M%S)"
DRY=0; FULL=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --full)       FULL=1 ;;
    --force|-f)   FORCE=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
run()  { if ((DRY)); then echo "    [dry-run] $*"; else "$@"; fi; }

[[ -f "$MANIFEST" ]] || {
  warn "no change log at $MANIFEST"
  echo "    install.sh writes it; without it there's nothing to reverse."
  echo "    Backups are still on disk as <name>.bak-<timestamp> if you want to"
  echo "    put them back by hand."
  exit 1
}

# q <query>: pull one thing out of the manifest
q() { MANIFEST="$MANIFEST" python3 -c "$1"; }

restored=0; skipped=0

# --- 1. configs -------------------------------------------------------------
# One line per path, keeping the EARLIEST record for each: that's the one
# holding the true original state, since a later run may have seen only our own
# symlink, or recorded a prior we made ourselves.
say "configs (from $MANIFEST)"
# \x1f, not tab: tab is IFS whitespace, so runs of it collapse and a record with
# an empty middle field would shift its remaining fields left.
while IFS=$'\x1f' read -r action path ptype detail sha target; do
  [[ -n "$path" ]] || continue

  # take away what install.sh put there, if it's still ours. Branch on the
  # action: a copy record also carries a target (the example it came from).
  if [[ "$action" == "link" ]]; then
    if [[ -L "$path" ]]; then
      current="$(readlink "$path")"
      if [[ "$current" == "$target" ]]; then
        run rm "$path"
      elif ((FORCE)); then
        warn "$path points at $current, not ours; removing anyway (--force)"
        run rm "$path"
      else
        warn "skip $path — points at $current, not $target"
        skipped=$((skipped + 1)); continue
      fi
    elif [[ -e "$path" ]]; then
      if ((FORCE)); then
        warn "$path is no longer a symlink; moving it aside (--force)"
        run mv "$path" "$path.uninstall-$STAMP"
      else
        warn "skip $path — not a symlink any more, left alone"
        skipped=$((skipped + 1)); continue
      fi
    fi
  elif [[ "$action" == "copy" ]]; then
    # install.sh created this from an example: remove it only if untouched,
    # otherwise keep the edits by moving it aside.
    if [[ -e "$path" ]]; then
      if [[ -f "$target" ]] && cmp -s "$path" "$target"; then
        run rm "$path"
      else
        echo "    kept your edits: $path -> $path.uninstall-$STAMP"
        run mv "$path" "$path.uninstall-$STAMP"
      fi
    fi
  fi
  # a remove/backup record created nothing, so there is nothing to take away

  # put back whatever was displaced
  case "$ptype" in
    symlink)
      echo "    restore $path -> $detail"
      run mkdir -p "$(dirname "$path")"
      run ln -s "$detail" "$path"
      restored=$((restored + 1))
      ;;
    file|dir)
      if [[ -e "$detail" ]]; then
        echo "    restore $path (from $(basename "$detail"))"
        run mkdir -p "$(dirname "$path")"
        run mv "$detail" "$path"
        # verify against the checksum taken before it was moved
        if [[ -n "$sha" && -f "$path" ]] && ((!DRY)); then
          now="$(shasum -a 256 "$path" | cut -d' ' -f1)"
          [[ "$now" == "$sha" ]] || warn "checksum differs for $path (recorded $sha, got $now)"
        fi
        restored=$((restored + 1))
      else
        warn "backup missing for $path: $detail"
        skipped=$((skipped + 1))
      fi
      ;;
    absent)
      echo "    removed  $path (nothing was there before)"
      restored=$((restored + 1))
      ;;
    *)
      warn "unknown prior type '$ptype' for $path"
      skipped=$((skipped + 1))
      ;;
  esac
done < <(q '
import json, os, sys
data = json.load(open(os.environ["MANIFEST"]))
first, order = {}, []
for r in data.get("runs", []):
    for a in r.get("actions", []):
        p = a.get("path")
        if p and p not in first:
            first[p] = a; order.append(p)
for p in order:
    a = first[p]; pr = a.get("prior", {})
    print("\x1f".join([a.get("action",""), p, pr.get("type",""),
                       pr.get("target","") or pr.get("backup",""),
                       pr.get("sha256",""), a.get("target","")]))
')

# --- 2. cli-tools and its binaries -----------------------------------------
say "cli-tools"
CLI_TOOLS="$(q 'import json,os;d=json.load(open(os.environ["MANIFEST"]));print(next((r.get("cli_tools","") for r in reversed(d.get("runs",[])) if r.get("cli_tools")),""))')"

# Committing and pushing is the author's business, so this doesn't second-guess
# an unsaved change; it's a checkout of a remote repo and install.sh re-clones it.
if [[ -n "$CLI_TOOLS" && -d "$CLI_TOOLS" ]]; then
  echo "    delete $CLI_TOOLS"
  run rm -rf "$CLI_TOOLS"
  restored=$((restored + 1))
else
  echo "    no checkout to remove"
fi

# Absolute paths, recorded as each was built, so this covers whichever toolchain
# produced it — go's $GOPATH/bin, cargo's $CARGO_HOME/bin, or anything added later.
while read -r b; do
  [[ -n "$b" ]] || continue
  if [[ -e "$b" ]]; then
    echo "    delete $b"
    run rm -f "$b"
    restored=$((restored + 1))
  fi
done < <(q 'import json,os;d=json.load(open(os.environ["MANIFEST"]));print("\n".join(sorted({b for r in d.get("runs",[]) for b in r.get("binaries",[])})))')

# --- 3. --full: packages this repo added ------------------------------------
if ((FULL)); then
  say "packages (--full)"
  added_f="$(q 'import json,os;d=json.load(open(os.environ["MANIFEST"]));print(" ".join(sorted({x for r in d.get("runs",[]) for x in r.get("versions",{}).get("added",{}).get("formulae",[])})))')"
  added_c="$(q 'import json,os;d=json.load(open(os.environ["MANIFEST"]));print(" ".join(sorted({x for r in d.get("runs",[]) for x in r.get("versions",{}).get("added",{}).get("casks",[])})))')"
  # Never remove a language runtime or toolchain. brew's python is linked
  # against by other formulae, the system has its own that must not be touched,
  # and taking out go/node/php breaks far more than this repo set up. Nothing
  # a clean uninstall buys is worth that risk.
  # brew/homebrew first: Homebrew isn't a formula, so `brew uninstall brew`
  # would only error, but never let it be attempted. Then the language runtimes
  # and toolchains, for the reasons above.
  PROTECTED='^(brew|homebrew|python([0-9@.]*)?|go|golang|node|nodejs|php|ruby|perl|rust|rustup|openjdk([@.0-9]*)?|lua|deno|bun|julia|erlang|elixir|zig|dotnet|mono)$'
  keep=(); drop=()
  for f in $added_f; do
    if [[ "$f" =~ $PROTECTED ]]; then keep+=("$f"); else drop+=("$f"); fi
  done
  if ((${#keep[@]})); then
    warn "left installed (language/toolchain, removing it could break the system):"
    echo "        ${keep[*]}"
  fi
  if ((${#drop[@]})); then
    echo "    uninstall formulae: ${drop[*]}"
    # no --ignore-dependencies: let brew refuse anything still depended on
    run brew uninstall --formula "${drop[@]}" || warn "some formulae wouldn't uninstall (still depended on?)"
  else
    echo "    no formulae to uninstall"
  fi
  if [[ -n "$added_c" ]]; then
    echo "    uninstall casks: $added_c"
    # shellcheck disable=SC2086
    run brew uninstall --cask $added_c || warn "some casks wouldn't uninstall"
  else
    echo "    no casks were added by this repo"
  fi

  # Upgrades aren't reversed automatically — pinning an old version is a
  # deliberate act — but say what changed so it can be done by hand.
  changed="$(q '
import json, os
d = json.load(open(os.environ["MANIFEST"]))
out = []
for r in d.get("runs", []):
    ch = r.get("versions", {}).get("changed", {})
    for kind in ("formulae", "casks"):
        for name, v in sorted(ch.get(kind, {}).items()):
            out.append("        %-28s %s -> %s" % (name, v.get("from",""), v.get("to","")))
print("\n".join(out))
')"
  if [[ -n "$changed" ]]; then
    warn "these were upgraded during install; not downgraded automatically:"
    echo "$changed"
  fi

  if command -v uv >/dev/null && uv tool list 2>/dev/null | grep -q '^mp3book'; then
    echo "    uv tool uninstall mp3book"
    run uv tool uninstall mp3book || warn "mp3book uninstall failed"
  fi
  echo "    vim plugins live in the repo (vim/plugged); delete the repo to remove them"
fi

# --- summary ----------------------------------------------------------------
say summary
echo "    $restored reverted, $skipped skipped"
if ((DRY)); then
  echo "    (dry run: nothing changed)"
  exit 0
fi
warn "the change log is kept at $MANIFEST"
echo "    it holds the versions of everything at install time; delete it once"
echo "    you're happy, or re-run install.sh to start a new one."
((FULL)) || cat <<'EOF'

    Left in place (use --full to remove):
      brew packages this repo installed
      mp3book
      vim plugins
EOF
