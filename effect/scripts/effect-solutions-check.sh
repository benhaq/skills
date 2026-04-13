#!/usr/bin/env bash
set -euo pipefail

if ! command -v effect-solutions &>/dev/null; then
  echo "effect-solutions CLI not found. Install: bun add -g effect-solutions"
  echo "Skipping compliance check."
  exit 0
fi

TOPICS="services-and-layers data-modeling error-handling testing tsconfig project-setup"

echo "## effect-solutions Compliance Check"
echo ""
for topic in $TOPICS; do
  echo "### $topic"
  if output=$(effect-solutions show "$topic" 2>&1); then
    echo '```'
    echo "$output"
    echo '```'
  else
    echo "Could not fetch: $topic"
  fi
  echo ""
done
