#!/usr/bin/env bash

function fix_package_manager() {
    case "$OS" in
        ubuntu)
            if (( VER < 20 )); then
                sed -i 's/archive.ubuntu.com/old-releases.ubuntu.org/g' /etc/apt/sources.list
                sed -i 's/security.ubntu.com/old-releases.ubuntu.org/g' /etc/apt/sources.list
            fi
            ;;
        debian)
            if (( VER <= 10 )); then
                sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list
                sed -i 's/security.debian.org/archive.debian.org/g' /etc/apt/sources.list
                sed -i '/stretch-updates/d' /etc/apt/sources.list
            fi
            ;;
        fedora)
            if (( VER <=38 )); then
                sed -i -E 's/^(metalink|mirrorlist)=/#\0/' /etc/yum.repos.d/fedora*.repo 
                sed -i -E "/^\[fedora\]/,/^\[/{s|^[# ]*baseurl=.*|baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/\$releasever/Everything/\$basearch/os/}; /^\[updates\]/,/^\[/{s|^[# ]*baseurl=.*|baseurl=https://archives.fedoraproject.org/pub/archive/fedora/linux/updates/\$releasever/Everything/\$basearch/}" /etc/yum.repos.d/fedora.repo /etc/yum.repos.d/fedora-updates.repo
            fi
            ;;
        centos)
            if (( VER <= 8 )); then
                sed -i -E 's|mirror\.centos\.org|vault.centos.org|g; s|^#baseurl=http://vault|baseurl=http://vault|' /etc/yum.repos.d/*.repo
            fi
            ;;
    esac
}
