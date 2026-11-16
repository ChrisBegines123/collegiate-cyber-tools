#!/bin/bash
hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown"
