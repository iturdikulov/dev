#!/usr/bin/env bash

# Verify that we are have required commands
command -v gpg >/dev/null 2>&1 || { echo >&2 "Please install gnupg."; exit 1; }

# Configuration
BACKUP_DIR="$HOME/gpg_backup"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_KEYS="$BACKUP_DIR/gpg_keys_$TIMESTAMP.tar.gz.gpg"
BACKUP_GNUPG="$BACKUP_DIR/gnupg_folder_$TIMESTAMP.tar.gz.gpg"

# Function: Read password and confirm
read_password() {
    read -s -p "Please enter the password for encrypted backup: " BACKUP_PASS
    echo
    read -s -p "Please enter the password again: "  BACKUP_PASS_CONFIRM
    echo
    if [[ "$BACKUP_PASS" != "$BACKUP_PASS_CONFIRM" ]]; then
        echo "Error: The passwords entered twice do not match!"
        exit 1
    fi
}

# Function: Back up GPG key
backup_keys() {
    # Verify that backup dir empty
    if [[ -n "$(ls -A "$BACKUP_DIR")" ]]; then
        echo "Error: Backup directory is not empty, please move all files in it"
        exit 1
    fi

    echo "Backing up GPG keys..."
    read_password

    # Export public and private keys
    gpg --export --export-options export-backup --armor --output "$BACKUP_DIR/gpg_public_keys_$TIMESTAMP.pub"
    gpg --export-secret-keys --export-options export-backup --armor --output "$BACKUP_DIR/gpg_private_keys_$TIMESTAMP.asc"
    gpg --export-secret-subkeys --export-options export-backup --armor --output "$BACKUP_DIR/gpg_private_sub_$TIMESTAMP.asc"

    # The GPG Trust Database is used to keep the trust values for each of the
    # Public Keys you have.
    gpg --export-ownertrust > "$BACKUP_DIR/all_keys_ownertrust.txt"

    # Pack and encrypt all files in the backup directory
    tar -czvf - -C "$BACKUP_DIR" . | \
        gpg --symmetric --cipher-algo AES256 --batch --passphrase "$BACKUP_PASS" -o "$BACKUP_KEYS"

    # Clean up temporary files
    rm "$BACKUP_DIR/gpg_public_keys_$TIMESTAMP.pub" "$BACKUP_DIR/gpg_private_keys_$TIMESTAMP.asc" "$BACKUP_DIR/gpg_private_sub_$TIMESTAMP.asc" "$BACKUP_DIR/all_keys_ownertrust.txt"

    echo "GPG keys backed up to: $BACKUP_KEYS"
}

# Function: backup ~/.gnupg folder
backup_gnupg() {
    echo "Backing up ~/.gnupg folder..."
    read_password

    # Pack and encrypt
    tar -czvf - -C "$HOME" .gnupg | \
        gpg --symmetric --cipher-algo AES256 --batch --passphrase "$BACKUP_PASS" -o "$BACKUP_GNUPG"

    echo "~/.gnupg folder has been backed up to: $BACKUP_GNUPG"
}

# Function: Import backup GPG key
import_keys() {
    echo "Importing GPG key..."
    read -p "Please enter the backup file absolute path (/home/...): " BACKUP_FILE
    BACKUP_FILE=$(realpath $BACKUP_FILE)

    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "Error: backup file does not exist! "
        exit 1
    fi

    read -s -p "Please enter the backup file password: " BACKUP_PASS
    echo

    # Automatically find the key file when decompressing
    BACKUP_TMP_DIR=$(mktemp -d)
    trap "rm -rf $BACKUP_TMP_DIR" EXIT

    # Decrypt and import
    gpg --decrypt --batch --passphrase "$BACKUP_PASS" "$BACKUP_FILE" | tar -xzvf - -C "$BACKUP_TMP_DIR"

    # Ask to import the key
    read -p "Do you want to import the GPG key, they are already extracted in $BACKUP_TMP_DIR [y/n]: " IMPORT_KEY_Q
    case $IMPORT_KEY_Q in
        [Yy]* )
            ;;
        * )
            echo "GPG key import aborted!"
            exit 1
            ;;
    esac

    gpg --import "$BACKUP_TMP_DIR"/*.asc
    gpg --import "$BACKUP_TMP_DIR"/*.pub
    gpg --import-ownertrust "$BACKUP_TMP_DIR/all_keys_ownertrust.txt"
    echo "GPG key import completed! "
}

# Main menu
echo "Please select an operation:"
echo "1. Backup GPG key"
echo "2. Backup ~/.gnupg folder. Highly important for revoke keys! ~/.gnupg/openpgp-revocs.d/"
echo "3. Import the backed up GPG key"
read -p "Input options (1/2/3): " OPTION

case $OPTION in
    1)
        backup_keys
        ;;
    2)
        backup_gnupg
        ;;
    3)
        import_keys
        ;;
    *)
        echo "Error: Invalid option! "
        exit 1
        ;;
esac
