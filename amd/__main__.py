"""Command line: `python -m amd <command>`."""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m amd", description="AustriaMacroData pipeline")
    sub = parser.add_subparsers(dest="command", required=True)

    reg = sub.add_parser("registry", help="the AMD registry in registry/")
    reg_sub = reg.add_subparsers(dest="action", required=True)
    check = reg_sub.add_parser("check", help="validate the registry; exit 1 on any broken rule")
    check.add_argument("--dir", default="registry")
    fetch = reg_sub.add_parser("fetch-external",
                               help="refresh the cached copies of the external artefacts (needs the network)")
    fetch.add_argument("--dir", default="registry")
    fetch.add_argument("--only", help="one artefact, e.g. 'SDMX:CL_FREQ(2.1)'")

    args = parser.parse_args(argv)

    if args.command == "registry" and args.action == "check":
        from amd.registry import Registry

        errors = Registry.load(args.dir).validate()
        for e in errors:
            print(e)
        print(f"{len(errors)} error(s)" if errors else "registry is valid")
        return 1 if errors else 0

    if args.command == "registry" and args.action == "fetch-external":
        from amd.external import fetch_external

        outcome = fetch_external(args.dir, only=args.only)
        for artefact, result in outcome.items():
            print(f"{artefact}: {result}")
        return 1 if any(r.startswith("FAILED") for r in outcome.values()) else 0

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    sys.exit(main())
