#!/usr/bin/env python3
import json, os, re, sys

data_dir = os.environ.get("alfred_workflow_data")
os.makedirs(data_dir, exist_ok=True)

CONFIG = os.path.join(data_dir, "desktops.json")
CONFIG = os.path.expanduser(CONFIG)

import json, os, shutil, tempfile

query = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
q = query.lower()

# load map
# load + normalize map (read-only)
try:
    with open(CONFIG) as f:
        raw = json.load(f) or {}
except Exception:
    raw = {}

m = {}
if isinstance(raw, dict):
    for k, v in raw.items():
        try:
            name = str(k).strip()
            n = int(v)
            if name and 1 <= n <= 9:
                m[name] = n
        except Exception:
            pass
else:
    m = {}

m = {}
for k, v in (raw or {}).items():
    try:
        m[str(k).strip()] = int(v)
    except Exception:
        pass

items = []

def add_help_items(items):
    items.append({
        "title": "Naming:",
        "subtitle": "Create or update: desk <name> <1-9>   (example: desk music 2)",
        "valid": False
    })
    items.append({
        "title": "Switching:",
        "subtitle": "Go: desk <name>   or   desk <1-9>",
        "valid": False
    })
    items.append({
        "title": "Deleting:",
        "subtitle": "On a mapping: hold ⌥ and press Enter",
        "valid": False
    })

help_mode = q in ("help", "?", "setup")

if help_mode:
    add_help_items(items)
    print(json.dumps({"items": items}))
    raise SystemExit(0)

if not q:
    add_help_items(items)

m_go = re.match(r"^([1-9])\s*$", query)
if m_go:
    num = int(m_go.group(1))
    items.append({
        "title": f"Go to Desktop {num}",
        "subtitle": "Enter to switch",
        "arg": str(num),
        "valid": True,
        "match": f"go {num} desktop {num}"
    })

# Allow "name 3" or "name=3" or "name:3"
m_set = re.match(r"^(.*\S)\s*(?:[=:]\s*|\s+)([1-9])\s*$", query)
if m_set:
    name = m_set.group(1).strip()
    num = int(m_set.group(2))

    old = next((k for k, v in m.items()
                if int(v) == num and k.lower() != name.lower()), None)
    subtitle = "Enter to save mapping" + (f" (replaces: {old})" if old else "")

    items.append({
        "title": f"Set: {name} → Desktop {num}",
        "subtitle": subtitle,
        "arg": f"__set__:{name}:{num}",
        "valid": True,
        "match": f"set {name} {num}"
    })

# Filter existing items if query present
def matches(name, n):
    if not q:
        return True
    s = f"{name} {n}".lower()
    return q in s

for name, n in sorted(m.items(), key=lambda kv: (kv[1], kv[0].lower())):
    if not matches(name, n):
        continue
    items.append({
        "title": f"{n}. {name}",
        "subtitle": f"Switch to Desktop {n}",
        "arg": name,
        "match": f"{name} desktop {n}",
        "mods": {
            "alt": {
                "valid": True,
                "arg": f"__rm__:{name}",
                "subtitle": f"Remove mapping for {name}"
            }
        }
    })

# If nothing matched and not a set command, show a hint so you don't fall back to Google
if q and not m_set and len(items) == 0:
    items.append({
        "title": f'No desktop named "{query}"',
        "subtitle": 'Create it by typing: desk <name> <1-9>  (example: desk music 2)',
        "arg": "__noop__",
        "valid": False,
        "match": query
    })

# If empty query and no items, show a starter hint
if not q and len(items) == 0:
    items.append({
        "title": "No desktops configured",
        "subtitle": 'Create one by typing: desk <name> <1-9>  (example: desk music 2)',
        "arg": "__noop__",
        "valid": False
    })

print(json.dumps({"items": items}))
