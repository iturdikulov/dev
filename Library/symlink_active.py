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
        print(f"Created symlink directory: {SYMLINK_DIR}")

def sanitize_filename(filename):
    # Normalize to ASCII
    filename = unicodedata.normalize('NFKD', filename).encode('ascii', 'ignore').decode('ascii')
    # Replace spaces with underscores
    filename = filename.replace(' ', '_')
    # Remove commas and disallowed characters
    filename = re.sub(r'[^A-Za-z0-9_\-\.]', '', filename)
    return filename

def process_library(library_path, tag_to_find):
    calibre_db = db(library_path).new_api
    found = False

    for book_id in calibre_db.all_book_ids():
        mi = calibre_db.get_metadata(book_id)
        tags = [t.lower() for t in mi.tags]
        if tag_to_find in tags:
            formats = calibre_db.formats(book_id)
            if formats:
                fmt = "PDF" if "PDF" in formats else formats[0]
                filepath = calibre_db.format_abspath(book_id, fmt)
                original_filename = os.path.basename(filepath)
                sanitized_filename = sanitize_filename(original_filename)
                symlink_path = os.path.join(SYMLINK_DIR, sanitized_filename)

                try:
                    if not os.path.exists(symlink_path):
                        os.symlink(filepath, symlink_path)
                        print(f"Symlink created: {symlink_path}")
                    else:
                        print(f"Symlink already exists: {symlink_path}")

                    found = True
                except OSError as e:
                    print(f"Error creating symlink: {e}")

    if not found:
        print(f"No books found with tag: {tag_to_find}")

def main():
    ensure_symlink_dir()
    for library_path in CALIBRE_LIBRARY_LOCATIONS:
        if os.path.exists(library_path):
            process_library(library_path, TAG_TO_FIND)
        else:
            print(f"Library not found: {library_path}")

main()
