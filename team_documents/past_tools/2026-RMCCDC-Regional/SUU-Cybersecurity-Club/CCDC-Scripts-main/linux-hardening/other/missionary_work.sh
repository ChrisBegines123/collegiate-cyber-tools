#!/usr/bin/env bash

release_version=$(curl -fsSL https://api.github.com/repos/SUU-Cybersecurity-Club/CCDC_Bible/releases/latest | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\2/p' | head -n1)

function spread_word_of_god() {
    wget https://github.com/SUU-Cybersecurity-Club/CCDC_Bible/releases/latest/download/"$release_version"/ccdc-bible-"$release_version".pdf
    
    for dir in /home/*; do
        if [ -d "$dir" ]; then
            cp ccdc-bible-"$release_version".pdf "$dir"
        fi
    done
}
