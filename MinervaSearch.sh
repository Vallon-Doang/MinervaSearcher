#!/usr/bin/env bash

# Ensure aria2c is installed
if ! command -v aria2c &> /dev/null; then
    echo "Error: aria2c is not installed. Please install it first."
    exit 1
fi

select_torrent_file() {
    shopt -s nullglob
    local torrents=(*.torrent)
    shopt -u nullglob

    if [[ ${#torrents[@]} -eq 0 ]]; then
        echo "Error: No .torrent files found in current directory ($(pwd))."
        return 1
    fi

    echo ""
    echo "Select a .torrent file from the current directory:"
    for i in "${!torrents[@]}"; do
        echo "  $((i+1)). ${torrents[$i]}"
    done

    echo -n "Enter selection [1-${#torrents[@]}]: "
    read -r INDEX

    if [[ ! "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt "${#torrents[@]}" ]; then
        echo "Invalid selection."
        return 1
    fi

    SELECTED_TORRENT="${torrents[$((INDEX-1))]}"
    echo "Selected torrent: $SELECTED_TORRENT"
    echo ""
}

while true; do
    echo "=================================="
    echo "   Minerva ISO Downloader Menu    "
    echo "=================================="
    echo "1. Search for a game (Find ID)"
    echo "2. Download game by ID"
    echo "3. Exit"
    echo "----------------------------------"
    echo -n "Select an option [1-3]: "
    read -r CHOICE

    case "$CHOICE" in
        1)
            select_torrent_file || continue

            echo -n "Enter game name to search: "
            read -r QUERY

            if [[ -z "$QUERY" ]]; then
                echo "Search query cannot be empty."
                continue
            fi

            echo ""
            echo "--- Search Results ---"
            
            # Use aria2c output and apply safe multi-word case-insensitive matching
            aria2c -S "$SELECTED_TORRENT" | awk -v q="$QUERY" '
            BEGIN {
                # Split search string into word array
                n = split(tolower(q), words, " ")
            }
            {
                line_lower = tolower($0)
                match_all = 1
                for (i = 1; i <= n; i++) {
                    if (index(line_lower, words[i]) == 0) {
                        match_all = 0
                        break
                    }
                }
                if (match_all && $0 ~ /^[ ]*[0-9]+/) {
                    print $0
                }
            }'

            echo "----------------------"
            echo ""
            ;;

        2)
            select_torrent_file || continue

            echo -n "Enter the File ID (Index number): "
            read -r GAME_ID

            if [[ ! "$GAME_ID" =~ ^[0-9]+$ ]]; then
                echo "Error: ID must be a valid number."
                continue
            fi

            echo -n "Enter download destination directory [default: ./Downloads]: "
            read -r OUT_DIR
            OUT_DIR=${OUT_DIR:-"./Downloads"}

            # Extract relative path of target file directly from torrent index
            TARGET_PATH=$(aria2c -S "$SELECTED_TORRENT" | awk -v id="$GAME_ID" '
                $0 ~ "^[ ]*" id "\\|" {
                    sub(/^[ ]*[0-9]+\|/, "");
                    print $0
                }
            ')

            echo ""
            echo "Starting download for File ID $GAME_ID..."
            aria2c --select-file="$GAME_ID" \
                   --seed-time=0 \
                   --file-allocation=none \
                   -d "$OUT_DIR" \
                   "$SELECTED_TORRENT"

            echo ""
            echo "Flattening directory structure..."

            # If target path matches, move directly
            if [[ -n "$TARGET_PATH" && -f "$OUT_DIR/$TARGET_PATH" ]]; then
                mv "$OUT_DIR/$TARGET_PATH" "$OUT_DIR/" 2>/dev/null
            else
                # Fallback: move any real downloaded file (>0 bytes) in subdirectories to top of OUT_DIR
                find "$OUT_DIR" -mindepth 2 -type f -size +0c -exec mv {} "$OUT_DIR/" \; 2>/dev/null
            fi

            # Remove empty 0-byte ghost files created by piece boundaries
            find "$OUT_DIR" -type f -size 0 -delete 2>/dev/null
            
            # Clean up empty directories
            find "$OUT_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null

            echo "Operation complete. File saved to: $OUT_DIR/"
            echo ""
            ;;

        3)
            echo "Exiting..."
            exit 0
            ;;

        *)
            echo "Invalid option, please choose 1, 2, or 3."
            echo ""
            ;;
    esac
done