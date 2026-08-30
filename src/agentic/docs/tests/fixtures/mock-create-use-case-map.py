#!/usr/bin/env python3
"""Mock create-use-case-map.py for testing the TS wrapper."""
import argparse, json, sys

parser = argparse.ArgumentParser()
parser.add_argument("--project-root", "-r", default=".")
parser.add_argument("--output", "-o", default="")
parser.add_argument("--component", "-c", default="")
parser.add_argument("--title", "-t", default="")
parser.add_argument("--subtitle", "-s", default="")
parser.add_argument("--copy-visualizer", default="")
args = parser.parse_args()

# Print info to stderr (matches real script behavior)
print(f"Scanning: {args.project_root}", file=sys.stderr)
if args.component:
    print(f"Component filter: {args.component}", file=sys.stderr)

# Output mock JSON
result = {
    "$schema": "",
    "title": args.title or "Mock Map",
    "subtitle": args.subtitle or "Mock subtitle",
    "items": []
}
output = json.dumps(result, indent=2)

if args.output:
    with open(args.output, "w") as f:
        f.write(output)
    print(f"Written: {args.output}", file=sys.stderr)
else:
    print(output)
