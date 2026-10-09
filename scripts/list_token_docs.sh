#!/bin/bash
# List token/context/slicing planning docs. The planning docs are kept in the
# private internal docs overlay; pass the docs root as the first argument
# (default: docs).
d="${1:-docs}"
[ -d "$d" ] || { echo "no docs directory: $d" >&2; exit 1; }
ls "$d"/brainstorms/*token* "$d"/plans/*tldrs* "$d"/brainstorms/*context* "$d"/plans/*context* "$d"/brainstorms/*slicing* "$d"/plans/*slicing* 2>/dev/null
