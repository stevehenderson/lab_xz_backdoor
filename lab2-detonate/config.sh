# shellcheck shell=bash
# shellcheck disable=SC2034  # every var here is consumed by setup.sh/teardown.sh which source this
# lab2-detonate/config.sh — shared configuration for the three-VM detonation lab.
# Sourced by setup.sh / teardown.sh (host side).

# Isolated L2 segment (no NAT, no internet). Created by setup.sh if absent.
BRIDGE="${BRIDGE:-xzbr0}"
SUBNET="${SUBNET:-10.77.0}"           # /24
BRIDGE_HOST_IP="${BRIDGE_HOST_IP:-${SUBNET}.1}"

# The three guests and their addresses on the isolated bridge.
ANALYST_VM="${ANALYST_VM:-analyst}"
COMPROMISED_VM="${COMPROMISED_VM:-compromised}"
NORMAL_VM="${NORMAL_VM:-normal}"
ANALYST_IP="${ANALYST_IP:-${SUBNET}.10}"
COMPROMISED_IP="${COMPROMISED_IP:-${SUBNET}.20}"
NORMAL_IP="${NORMAL_IP:-${SUBNET}.30}"

# Guest sizing. compromised needs room to install a backdoored liblzma; analyst
# builds Go. normal is tiny.
ANALYST_SPEC="--cpus 2 --memory 2G --disk 8G"
COMPROMISED_SPEC="--cpus 1 --memory 1G --disk 6G"
NORMAL_SPEC="--cpus 1 --memory 1G --disk 5G"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-22.04}"

# Where the lab payload lives inside every guest.
GUEST_DIR="/home/ubuntu/xzlab"

# Pinned upstream xzbot (trigger client + reference); verified after clone.
XZBOT_COMMIT="8ae5b706fb2c6040a91b233ea6ce39f9f09441d5"
# Backdoored liblzma5 5.6.1-1 (amd64), stable snapshot.debian.org file hash.
LIBLZMA_URL="https://snapshot.debian.org/file/81f1f56c590eee24bc320293f2c5c508fcb55d02"
