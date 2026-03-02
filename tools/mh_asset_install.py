#!/usr/bin/env python3
"""Download and install MakeHuman community asset packs into MPFB2.

Fetches zip archives from MakeHuman community mirrors and extracts them
into the MPFB2 data directory so they're available for blueprint clothing
and equipment loading.

Usage:
    python3 tools/mh_asset_install.py suits02 shirts03 equipment01
    python3 tools/mh_asset_install.py --list
    python3 tools/mh_asset_install.py --status
"""

import argparse
import json
import os
import platform
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

# Known asset packs: name -> {url_template, license, description, size_mb}
KNOWN_PACKS = {
    "suits02": {
        "filename": "suits02_cc0.zip",
        "license": "CC0",
        "description": "Viking tunics, monk robes, sci-fi suits",
        "size_mb": 183,
        "notable": [
            "rehmanpolanski_viking_tunic",
            "rehmanpolanski_viking_pants",
            "rehmanpolanski_viking_boots",
            "donitz_monk_robe",
        ],
    },
    "shirts03": {
        "filename": "shirts03_ccby.zip",
        "license": "CC-BY",
        "description": "Tunics, tank tops, peasant blouses",
        "size_mb": 68,
        "notable": [
            "drednicolson_asymmetric_tunic_and_sash",
            "elvs_ruffle_sleeve_peasant_blouse_1",
        ],
    },
    "equipment01": {
        "filename": "equipment01_cc0.zip",
        "license": "CC0",
        "description": "Weapons: bow, sword, hammer, dagger, claws",
        "size_mb": 17,
        "notable": [
            "culturalibre_wooden_bow",
            "joepal_crude_sword",
            "culturalibre_war_hammer",
        ],
    },
    "underwear04": {
        "filename": "underwear04_cc0.zip",
        "license": "CC0",
        "description": "Socks and leg wraps (primitive boot alternatives)",
        "size_mb": 5,
        "notable": [
            "joepal_crude_high_socks",
            "toigo_leg_warmer_socks",
        ],
    },
    "poses02": {
        "filename": "poses02_cc0.zip",
        "license": "CC0",
        "description": "Sport poses including archer stances",
        "size_mb": 1,
        "notable": [
            "callharvey3d_archer_hero",
            "callharvey3d_archer_square_stance",
        ],
    },
    "haireditor": {
        "filename": "haireditor.zip",
        "license": "CC0",
        "description": "Geometry-node hair and fur templates for Blender",
        "size_mb": 12,
        "notable": ["hair.blend", "fur.blend"],
        "url_pattern": "functional",
    },
}

MIRRORS = [
    "https://files2.makehumancommunity.org",
    "https://files.makehumancommunity.org",
]

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTALLED_FILE = os.path.join(PROJECT_ROOT, "blender", "assets_installed.json")


def get_mpfb_data_dir():
    """Find the MPFB2 data directory for the current platform."""
    system = platform.system()
    if system == "Darwin":
        base = os.path.expanduser(
            "~/Library/Application Support/Blender"
        )
    elif system == "Linux":
        base = os.path.expanduser("~/.config/blender")
    elif system == "Windows":
        base = os.path.join(os.environ.get("APPDATA", ""), "Blender Foundation", "Blender")
    else:
        print(f"ERROR: Unsupported platform: {system}", file=sys.stderr)
        sys.exit(1)

    # Find highest Blender version directory
    if not os.path.isdir(base):
        print(f"ERROR: Blender config dir not found: {base}", file=sys.stderr)
        sys.exit(1)

    versions = []
    for entry in os.listdir(base):
        entry_path = os.path.join(base, entry)
        if os.path.isdir(entry_path):
            try:
                versions.append((tuple(int(x) for x in entry.split(".")), entry))
            except ValueError:
                continue

    if not versions:
        print(f"ERROR: No Blender version dirs found in {base}", file=sys.stderr)
        sys.exit(1)

    versions.sort(reverse=True)
    version_dir = versions[0][1]

    mpfb_data = os.path.join(
        base, version_dir, "extensions", "blender_org", "mpfb", "data"
    )
    if not os.path.isdir(mpfb_data):
        print(f"ERROR: MPFB2 data dir not found: {mpfb_data}", file=sys.stderr)
        print("  Is MPFB2 installed? Install it from Blender's extension manager.", file=sys.stderr)
        sys.exit(1)

    return mpfb_data


def get_download_url(pack_name, pack_info):
    """Build download URLs for an asset pack."""
    filename = pack_info["filename"]
    url_pattern = pack_info.get("url_pattern", "asset_packs")
    if url_pattern == "functional":
        return [f"{mirror}/functional/{filename}" for mirror in MIRRORS]
    return [f"{mirror}/asset_packs/{pack_name}/{filename}" for mirror in MIRRORS]


def download_pack(pack_name, pack_info):
    """Download an asset pack zip, trying mirrors in order."""
    urls = get_download_url(pack_name, pack_info)

    for url in urls:
        try:
            print(f"  Downloading from {url} ...")
            tmp = tempfile.NamedTemporaryFile(
                suffix=".zip", delete=False, prefix=f"mh_{pack_name}_"
            )
            urllib.request.urlretrieve(url, tmp.name)
            size_mb = os.path.getsize(tmp.name) / (1024 * 1024)
            print(f"  Downloaded: {size_mb:.1f} MB")
            return tmp.name
        except urllib.error.URLError as e:
            print(f"  Mirror failed: {e}")
            continue

    print(f"ERROR: All mirrors failed for {pack_name}", file=sys.stderr)
    return None


def extract_pack(zip_path, pack_name, pack_info, mpfb_data):
    """Extract an asset pack into the MPFB2 data directory.

    Asset packs contain subdirectories like clothes/, poses/, etc.
    We extract matching subdirectories into the MPFB2 data dir.
    """
    extracted = []
    with zipfile.ZipFile(zip_path, "r") as zf:
        members = zf.namelist()

        # Categorize by top-level directory
        categories = set()
        for m in members:
            parts = m.split("/")
            if len(parts) >= 2:
                categories.add(parts[0])

        # Known MPFB2 data subdirectories
        mpfb_subdirs = {"clothes", "poses", "rigs", "targets", "skins"}

        for category in categories:
            if category in mpfb_subdirs:
                dest = os.path.join(mpfb_data, category)
                os.makedirs(dest, exist_ok=True)

                category_members = [m for m in members if m.startswith(f"{category}/")]
                for member in category_members:
                    # Strip the category prefix — extract into the category dir
                    rel_path = member[len(category) + 1:]
                    if not rel_path:
                        continue
                    target = os.path.join(dest, rel_path)
                    if member.endswith("/"):
                        os.makedirs(target, exist_ok=True)
                    else:
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        with zf.open(member) as src, open(target, "wb") as dst:
                            shutil.copyfileobj(src, dst)
                        extracted.append(rel_path)

        # For haireditor pack (blend files at root level)
        if pack_info.get("url_pattern") == "functional":
            blend_dir = os.path.join(mpfb_data, "haireditor")
            os.makedirs(blend_dir, exist_ok=True)
            for member in members:
                if member.endswith(".blend"):
                    target = os.path.join(blend_dir, os.path.basename(member))
                    with zf.open(member) as src, open(target, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                    extracted.append(member)

    return extracted


def validate_mhclo_files(mpfb_data, notable_assets):
    """Check that expected .mhclo files are present after extraction."""
    found = []
    missing = []
    clothes_dir = os.path.join(mpfb_data, "clothes")

    for asset in notable_assets:
        if asset.endswith(".blend"):
            # Blend files go to haireditor subdir
            path = os.path.join(mpfb_data, "haireditor", asset)
            if os.path.isfile(path):
                found.append(asset)
            else:
                missing.append(asset)
            continue

        mhclo = os.path.join(clothes_dir, asset, f"{asset}.mhclo")
        if os.path.isfile(mhclo):
            found.append(asset)
        else:
            missing.append(asset)

    return found, missing


def load_installed():
    """Load the installed packs registry."""
    if os.path.isfile(INSTALLED_FILE):
        with open(INSTALLED_FILE) as f:
            return json.load(f)
    return {}


def save_installed(installed):
    """Save the installed packs registry."""
    os.makedirs(os.path.dirname(INSTALLED_FILE), exist_ok=True)
    with open(INSTALLED_FILE, "w") as f:
        json.dump(installed, f, indent=2)
        f.write("\n")


def cmd_install(pack_names):
    """Install one or more asset packs."""
    mpfb_data = get_mpfb_data_dir()
    print(f"MPFB2 data: {mpfb_data}")

    installed = load_installed()

    for pack_name in pack_names:
        if pack_name not in KNOWN_PACKS:
            print(f"ERROR: Unknown pack: {pack_name}", file=sys.stderr)
            print(f"  Available: {', '.join(sorted(KNOWN_PACKS))}", file=sys.stderr)
            sys.exit(1)

        pack_info = KNOWN_PACKS[pack_name]
        print(f"\n=== Installing {pack_name} ({pack_info['license']}) ===")
        print(f"  {pack_info['description']}")

        if pack_name in installed:
            print(f"  Already installed. Use --force to reinstall.")
            continue

        zip_path = download_pack(pack_name, pack_info)
        if not zip_path:
            sys.exit(1)

        try:
            extracted = extract_pack(zip_path, pack_name, pack_info, mpfb_data)
            print(f"  Extracted {len(extracted)} files")

            found, missing = validate_mhclo_files(
                mpfb_data, pack_info.get("notable", [])
            )
            if found:
                print(f"  Validated: {', '.join(found)}")
            if missing:
                print(f"  WARNING: Missing expected assets: {', '.join(missing)}")

            installed[pack_name] = {
                "license": pack_info["license"],
                "files_extracted": len(extracted),
                "notable_assets": found,
            }
        finally:
            os.unlink(zip_path)

    save_installed(installed)
    print(f"\nRegistry updated: {INSTALLED_FILE}")


def cmd_list():
    """List available asset packs."""
    installed = load_installed()
    print("Available MakeHuman community asset packs:\n")
    for name, info in sorted(KNOWN_PACKS.items()):
        status = "INSTALLED" if name in installed else "available"
        print(f"  {name:16s} [{info['license']:5s}] {info['size_mb']:4d} MB  "
              f"[{status}]")
        print(f"    {info['description']}")
        if info.get("notable"):
            print(f"    Key assets: {', '.join(info['notable'][:3])}")
        print()


def cmd_status():
    """Show installed pack status."""
    installed = load_installed()
    if not installed:
        print("No asset packs installed.")
        print("Run: ./tools/ror mh-install --list")
        return

    print(f"Installed packs ({len(installed)}):\n")
    for name, info in sorted(installed.items()):
        print(f"  {name}: {info['files_extracted']} files ({info['license']})")
        if info.get("notable_assets"):
            print(f"    Assets: {', '.join(info['notable_assets'])}")


def main():
    parser = argparse.ArgumentParser(
        description="Install MakeHuman community asset packs for MPFB2"
    )
    parser.add_argument(
        "packs", nargs="*", help="Pack names to install (e.g., suits02 shirts03)"
    )
    parser.add_argument(
        "--list", action="store_true", help="List available asset packs"
    )
    parser.add_argument(
        "--status", action="store_true", help="Show installed pack status"
    )
    parser.add_argument(
        "--force", action="store_true", help="Reinstall even if already present"
    )
    args = parser.parse_args()

    if args.list:
        cmd_list()
    elif args.status:
        cmd_status()
    elif args.packs:
        if args.force:
            installed = load_installed()
            for p in args.packs:
                installed.pop(p, None)
            save_installed(installed)
        cmd_install(args.packs)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
