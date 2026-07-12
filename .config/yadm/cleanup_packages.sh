#!/usr/bin/env bash
# Remove selected desktop/app packages that are no longer wanted.
# Safe to re-run; optional removals are skipped when the package is missing.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=runs/utils.sh
source "$script_dir/runs/utils.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0")

  Removes selected packages and local desktop overrides that are no longer wanted.

EOF
}

while (($# > 0)); do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
done

cleanup_gnome_terminal() {
    remove_desktop_and_package \
        "org.gnome.Terminal.desktop" \
        "gnome-terminal" \
        "GNOME Terminal"
}

cleanup_konsole() {
    remove_desktop_and_package \
        "org.kde.konsole.desktop" \
        "konsole" \
        "Konsole"
}

cleanup_gnome_maps() {
    remove_desktop_and_package \
        "org.gnome.Maps.desktop" \
        "gnome-maps" \
        "GNOME Maps"
}

cleanup_file_roller() {
    remove_desktop_and_package \
        "org.gnome.FileRoller.desktop" \
        "file-roller" \
        "File Roller"
}

cleanup_ark() {
    remove_desktop_and_package \
        "org.kde.ark.desktop" \
        "ark" \
        "Ark"
}

cleanup_baobab() {
    remove_desktop_and_package \
        "org.gnome.baobab.desktop" \
        "baobab" \
        "Disk Usage Analyzer"
}

cleanup_partition_manager() {
    remove_desktop_and_package \
        "org.kde.partitionmanager.desktop" \
        "partitionmanager" \
        "KDE Partition Manager"
}

cleanup_discover() {
    remove_desktop_and_package \
        "org.kde.discover.desktop" \
        "plasma-discover" \
        "KDE Discover"

    remove_desktop_and_package \
        "org.kde.discover.notifier.desktop" \
        "plasma-discover" \
        "KDE Discover notifier"

    remove_desktop_and_package \
        "org.kde.discover.urlhandler.desktop" \
        "plasma-discover" \
        "KDE Discover URL handler"

    remove_desktop_and_package \
        "org.kde.discover.apt.urlhandler.desktop" \
        "plasma-discover" \
        "KDE Discover APT URL handler"
}

cleanup_redshift() {
    remove_desktop_and_package \
        "redshift.desktop" \
        "redshift" \
        "Redshift"

    remove_desktop_and_package \
        "redshift-gtk.desktop" \
        "redshift-gtk" \
        "Redshift GTK"
}

cleanup_malcontent_control() {
    remove_desktop_and_package \
        "org.freedesktop.MalcontentControl.desktop" \
        "malcontent-gui" \
        "Parental Controls"
}

cleanup_connections() {
    remove_desktop_and_package \
        "org.gnome.Connections.desktop" \
        "gnome-connections" \
        "Connections"
}

cleanup_image_viewer() {
    remove_desktop_and_package \
        "org.gnome.Loupe.desktop" \
        "loupe" \
        "Image Viewer"
}

cleanup_document_viewer() {
    remove_desktop_and_package \
        "org.gnome.Evince.desktop" \
        "evince" \
        "Document Viewer"

    remove_desktop_and_package \
        "org.gnome.Evince-previewer.desktop" \
        "evince" \
        "Document Viewer Previewer"
}

cleanup_contacts() {
    remove_desktop_and_package \
        "org.gnome.Contacts.desktop" \
        "gnome-contacts" \
        "Contacts"
}

cleanup_calendar() {
    remove_desktop_and_package \
        "org.gnome.Calendar.desktop" \
        "gnome-calendar" \
        "Calendar"
}

cleanup_text_editor() {
    remove_desktop_and_package \
        "org.gnome.TextEditor.desktop" \
        "gnome-text-editor" \
        "Text Editor"
}

cleanup_videos() {
    remove_desktop_and_package \
        "org.gnome.Totem.desktop" \
        "totem" \
        "Videos"
}

cleanup_showtime() {
    remove_desktop_and_package \
        "org.gnome.Showtime.desktop" \
        "showtime" \
        "Showtime"
}

cleanup_tour() {
    remove_desktop_and_package \
        "org.gnome.Tour.desktop" \
        "gnome-tour" \
        "Tour"
}

cleanup_kcalc() {
    remove_desktop_and_package \
        "org.kde.kcalc.desktop" \
        "kcalc" \
        "KCalc"
}

cleanup_spectacle() {
    remove_desktop_and_package \
        "org.kde.spectacle.desktop" \
        "kde-spectacle" \
        "Spectacle"
}

cleanup_console() {
    remove_desktop_and_package \
        "org.gnome.Console.desktop" \
        "gnome-console" \
        "Console"
}

cleanup_foot() {
    local paths=(
        "/usr/local/bin/foot"
        "/usr/local/bin/footclient"
        "/usr/local/share/applications/foot.desktop"
        "/usr/local/share/applications/foot-server.desktop"
        "/usr/local/share/applications/footclient.desktop"
        "$HOME/.local/share/applications/foot_ext.desktop"
        "$HOME/.local/share/applications/leaf_foot.desktop"
        "/usr/local/etc/xdg/foot"
        "/usr/local/share/doc/foot"
        "/usr/local/share/foot"
    )

    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            log_info "Removing Foot path: $path"
            if [[ "$path" == /usr/local/* ]]; then
                sudo rm -rf "$path" || log_warn "Failed to remove $path"
            else
                rm -rf "$path" || log_warn "Failed to remove $path"
            fi
        fi
    done

    if package_installed foot; then
        log_info "Removing foot package..."
        remove_packages foot
    else
        log_warn "foot package not installed, skipping"
    fi
}

cleanup_shotwell() {
    remove_desktop_and_package \
        "org.gnome.Shotwell.desktop" \
        "shotwell" \
        "Shotwell"

    remove_desktop_and_package \
        "org.gnome.Shotwell-Viewer.desktop" \
        "shotwell" \
        "Shotwell Viewer"

    remove_desktop_and_package \
        "org.gnome.Shotwell.Auth.desktop" \
        "shotwell" \
        "Shotwell Authentication helper"
}

cleanup_korganizer() {
    remove_desktop_and_package \
        "org.kde.korganizer.desktop" \
        "korganizer" \
        "KOrganizer"

    remove_desktop_and_package \
        "korganizer-import.desktop" \
        "korganizer" \
        "KOrganizer Import"

    remove_desktop_and_package \
        "korganizer-view.desktop" \
        "korganizer" \
        "KOrganizer View"
}

remove_desktop_and_package() {
    local desktop_file="$1"
    local package_name="$2"
    local display_name="$3"
    local local_desktop="$HOME/.local/share/applications/$desktop_file"

    if [[ -f "$local_desktop" ]]; then
        log_info "Removing local $display_name desktop entry..."
        rm -f "$local_desktop" || log_warn "Failed to remove $local_desktop"
    fi

    if package_installed "$package_name"; then
        log_info "Removing $package_name package..."
        remove_packages "$package_name"
    else
        log_warn "$package_name not installed, skipping"
    fi
}

main() {
    log_info "Starting package cleanup"
    cleanup_gnome_terminal
    cleanup_konsole
    cleanup_gnome_maps
    cleanup_file_roller
    cleanup_ark
    cleanup_baobab
    cleanup_partition_manager
    cleanup_discover
    cleanup_redshift
    cleanup_malcontent_control
    cleanup_connections
    cleanup_image_viewer
    cleanup_document_viewer
    cleanup_contacts
    cleanup_calendar
    cleanup_text_editor
    cleanup_korganizer
    cleanup_videos
    cleanup_showtime
    cleanup_tour
    cleanup_kcalc
    cleanup_spectacle
    cleanup_console
    cleanup_foot
    cleanup_shotwell
    log_info "Finished package cleanup"
}

main "$@"
