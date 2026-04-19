#!/usr/bin/calibre-debug

import os
import re
import unicodedata
from calibre.library import db

CALIBRE_LIBRARY_LOCATIONS = [
    "Fiction",
    "IT",
    "Science"
]

TAG_TO_FIND = "active"
SYMLINK_DIR = os.path.expanduser("~/Wiki/library")

def ensure_symlink_dir():
    if not os.path.exists(SYMLINK_DIR):
        os.makedirs(SYMLINK_DIR)
        print(f"Created link directory: {SYMLINK_DIR}")

def sanitize_filename(filename):
    # Normalize to ASCII
    filename = unicodedata.normalize('NFKD', filename).encode('ascii', 'ignore').decode('ascii')
    # Replace spaces with underscores
    filename = filename.replace(' ', '_')
    # Remove commas and disallowed characters
    filename = re.sub(r'[^A-Za-z0-9_\-\.]', '', filename)
    return filename

def build_expected_map(tag_to_find):
    """sanitized basename -> calibre format path. First library in list wins on name collision."""
    mapping = {}
    for library_path in CALIBRE_LIBRARY_LOCATIONS:
        if not os.path.exists(library_path):
            print(f"Library not found: {library_path}")
            continue
        calibre_db = db(library_path).new_api
        found_in_lib = False
        for book_id in calibre_db.all_book_ids():
            mi = calibre_db.get_metadata(book_id)
            tags = [t.lower() for t in mi.tags]
            if tag_to_find not in tags:
                continue
            formats = calibre_db.formats(book_id)
            if not formats:
                continue
            found_in_lib = True
            fmt = "PDF" if "PDF" in formats else formats[0]
            filepath = calibre_db.format_abspath(book_id, fmt)
            original_filename = os.path.basename(filepath)
            sanitized_filename = sanitize_filename(original_filename)
            if sanitized_filename not in mapping:
                mapping[sanitized_filename] = filepath
        if not found_in_lib:
            print(f"No books found with tag: {tag_to_find} in {library_path}")
    return mapping

def ensure_hardlinks(mapping):
    for sanitized_name, filepath in mapping.items():
        link_path = os.path.join(SYMLINK_DIR, sanitized_name)
        try:
            if not os.path.exists(link_path):
                os.link(filepath, link_path)
                print(f"Hardlink created: {link_path}")
                continue
            try:
                if os.path.samefile(link_path, filepath):
                    print(f"Hardlink already exists: {link_path}")
                else:
                    print(f"Hardlink path exists (different file), skipping: {link_path}")
            except OSError:
                print(f"Hardlink path already exists: {link_path}")
        except OSError as e:
            print(f"Error creating hardlink: {e}")

def prune_orphans(mapping):
    try:
        names = os.listdir(SYMLINK_DIR)
    except OSError as e:
        print(f"Cannot list link directory: {e}")
        return
    for name in names:
        if name in mapping:
            continue
        full = os.path.join(SYMLINK_DIR, name)
        if os.path.isdir(full) and not os.path.islink(full):
            continue
        try:
            os.remove(full)
            print(f"Removed stale mirror entry: {full}")
        except OSError as e:
            print(f"Error removing stale path {full}: {e}")

def main():
    ensure_symlink_dir()
    mapping = build_expected_map(TAG_TO_FIND)
    ensure_hardlinks(mapping)
    prune_orphans(mapping)

main()
