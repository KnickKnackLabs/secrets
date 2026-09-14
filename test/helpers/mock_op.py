#!/usr/bin/env python3
"""Fake-only op CLI. Accept JSON templates, reject secret-valued argv writes."""

import json
import os
from pathlib import Path
import shutil
import sys
import uuid

args = sys.argv[1:]
if os.environ.get("MOCK_OP_LOG"):
    with open(os.environ["MOCK_OP_LOG"], "a") as log:
        log.write(json.dumps(args) + "\n")
if any(arg.startswith("value[") for arg in args):
    sys.exit("mock op: secret assignment in argv forbidden")
if args[:1] == ["account"]:
    print('{"name":"fake-account"}')
    sys.exit(0)
if args[:1] != ["item"]:
    sys.exit("mock op: unexpected command")
action = args[1]
if os.environ.get("MOCK_OP_FAIL") == action:
    sys.exit("fake-provider-error-containing-SECRET-SENTINEL")
vault = args[args.index("--vault") + 1] if "--vault" in args else "Agents"
root = Path(os.environ["MOCK_OP_STORE"]) / vault
root.mkdir(parents=True, exist_ok=True)


def identifier(title):
    return uuid.uuid5(uuid.NAMESPACE_URL, title).hex[:26]


def load(directory):
    title = str(directory.relative_to(root))
    metadata = directory / ".item.json"
    item = json.loads(metadata.read_text()) if metadata.exists() else {
        "id": identifier(title), "title": title,
        "category": "SECURE_NOTE", "vault": {"id": "fake-vault-id", "name": vault},
    }
    item["fields"] = [{"id": path.name, "label": path.name, "type": "CONCEALED",
                       "value": path.read_bytes().decode("utf-8")}
                      for path in sorted(directory.iterdir())
                      if path.is_file() and not path.name.startswith(".")]
    return item


directories = {path.parent for path in root.rglob("*")
               if path.is_file() and not path.name.startswith(".")}
items = [load(directory) for directory in sorted(directories)]
if action == "list":
    if os.environ.get("MOCK_OP_DUPLICATE") and items:
        items.append(items[0])
    print(json.dumps([{key: item[key] for key in ("id", "title", "vault", "category")}
                      for item in items]))
    sys.exit(0)
selector = args[2]
matches = [item for item in items if selector in (item["title"], item["id"])]
# Legacy migration fixtures can have field names other than value.
if not matches and (root / selector).is_dir():
    matches = [load(root / selector)]
if action in {"get", "edit", "delete"} and len(matches) != 1:
    sys.exit("mock op: item not found")
if action == "get":
    item = matches[0]
    if "--fields" in args:
        field = args[args.index("--fields") + 1]
        fields = [entry for entry in item["fields"] if entry["id"] == field]
        if len(fields) != 1:
            sys.exit("mock op: field not found")
        if "--format" in args:
            print(json.dumps(fields[0]))
        else:
            sys.stdout.write(fields[0]["value"])
    else:
        print(json.dumps(item))
elif action in {"edit", "create"}:
    item = json.load(sys.stdin)
    if action == "edit":
        assert selector == matches[0]["id"], "edit must use verified ID"
        assert item["id"] == selector
    else:
        assert selector == "-", "create expects stdin template"
        assert not any(old["title"] == item["title"] for old in items)
        item.update(id=identifier(item["title"]), vault={"id": "fake-vault-id", "name": vault})
    assert item["category"] == "SECURE_NOTE"
    directory = root / item["title"]
    assert root.resolve() in directory.resolve().parents
    directory.mkdir(parents=True, exist_ok=True)
    for field in item["fields"]:
        (directory / field["id"]).write_bytes(field["value"].encode("utf-8"))
    (directory / ".item.json").write_text(json.dumps(item))
    print(json.dumps(item))
elif action == "delete":
    shutil.rmtree(root / matches[0]["title"])
else:
    sys.exit("mock op: unsupported command")
