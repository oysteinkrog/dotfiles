import json, subprocess, sys

HOOK = str(__import__("pathlib").Path(__file__).with_name("rg-replace-guard.sh"))

cases = [
    # (command, should_block)
    ("rg -rln alpha src/", True),
    ("rg -lrn foo", True),
    ("rg -nr pat src/", True),
    ("rg -lr foo", True),
    ("fd -e cs . | xargs rg -rl pat", True),
    ("time rg -rn pat", True),
    ("cd x && rg -rl pat", True),
    ("rg -l pat", False),
    ("rg -n pat", False),
    ("rg -r X pat", False),
    ("rg --replace=X pat", False),
    ("rg -e pat --replace bar", False),
    ("grep -rln foo .", False),
    ("rg -ln foo src/", False),
    ("rg -io pat", False),
    ("rg -A 3 -B 2 pat", False),
    ("rg -rln x  # noqa: rg-replace", False),
    # a cluster belonging to a DIFFERENT command in the same compound line
    ("rg -n foo src/; grep -rn bar foundation/", False),
    ("grep -rn x . ; rg -l y", False),
    ("rg -n a && grep -rln b", False),
    # still caught when the cluster really is rg's, in a compound line
    ("grep -n x . ; rg -rln y", True),
    ("ls -la && rg -nr pat src/", True),
    # variable assignment prefix
    ("FOO=1 rg -rln pat", True),
    # data regions: the offending text appears but nothing invokes it
    ("echo 'rg -rln is wrong'", False),
    ('echo "never write rg -rln"', False),
    ("git commit -m \"fix\" -m \"line one\nrg -nr PATTERN PATH shifts args\"", False),
    ("python3 - <<'PY'\ncases = ['rg -rln x', 'rg -nr y']\nPY", False),
    ("git commit -F - <<'MSG'\nfix\n\nrg -nr PATTERN PATH shifts args\nMSG", False),
    ("cat <<EOF\nrg -rln example\nEOF", False),
]

# The failure that hurt most was not a missed detection: an apostrophe inside a
# comment terminated the shell script's quoted Python and made the hook a syntax
# error, which denied EVERY Bash call in the session until it was fixed with a
# file write. Check the script parses before checking what it detects.
syntax = subprocess.run(["bash", "-n", HOOK], capture_output=True, text=True)
if syntax.returncode != 0:
    print("FAIL hook is not valid bash:", syntax.stderr.strip())
    sys.exit(1)

fails = 0
for cmd, expect in cases:
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    out = subprocess.run([HOOK], input=payload, capture_output=True, text=True)
    blocked = bool(out.stdout.strip())
    if blocked != expect:
        fails += 1
        print(f"FAIL block={blocked} expect={expect}  {cmd!r}")
        if out.stderr.strip():
            print("   stderr:", out.stderr.strip()[:200])

print(f"{len(cases) - fails}/{len(cases)} correct")
sys.exit(1 if fails else 0)
