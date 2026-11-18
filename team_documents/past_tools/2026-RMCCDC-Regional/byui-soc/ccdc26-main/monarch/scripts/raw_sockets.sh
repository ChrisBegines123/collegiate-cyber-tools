#!/bin/bash
# Checks for open raw sockets (potential sniffers/backdoors)
ss -lnp | grep -i raw 2>/dev/null || echo "none"
