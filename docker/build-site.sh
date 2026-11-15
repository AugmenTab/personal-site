#!/bin/sh
# Default command of the site-build service: compile the generator and render
# the site into dist/. Runs inside the container (see compose.yaml).
set -eu

stack build
stack exec -- site build --out dist
