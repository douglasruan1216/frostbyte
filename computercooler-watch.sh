#!/bin/bash
# Launches FrostByte when one of your selected apps opens. The app manages
# itself and self-quits after a few minutes with none of those apps running
# (keeps the menu bar tidy), so this watcher never needs to quit it.
APP="$HOME/ComputerCooler/FrostByte.app"

# FrostByte writes the process names you picked (in "OPEN FROSTBYTE FOR THESE")
# here, one per line. If it's missing/empty we fall back to the defaults.
LIST="$HOME/ComputerCooler/launch-apps.txt"
DEFAULT_GAMES=("RobloxPlayer" "Geometry Dash")

while true; do
    if ! pgrep -x FrostByte >/dev/null 2>&1; then
        # Build the trigger list: the user's picks, or the defaults if none.
        triggers=()
        if [ -s "$LIST" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && triggers+=("$line")
            done < "$LIST"
        fi
        [ ${#triggers[@]} -eq 0 ] && triggers=("${DEFAULT_GAMES[@]}")

        for g in "${triggers[@]}"; do
            if pgrep -x "$g" >/dev/null 2>&1; then
                open "$APP"
                break
            fi
        done
    fi
    sleep 5
done
