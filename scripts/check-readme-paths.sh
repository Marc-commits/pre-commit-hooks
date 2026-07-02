#!/bin/bash
# Check README.md files for local filesystem paths and bare GitHub repo mentions.
# Exits 1 if issues found, 0 otherwise.

found_any=0
for file in "$@"; do
  line_no=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    warned=0

    # Windows drive path (C:\, D:\, etc.)
    if printf "%s\n" "$line" | grep -qE "[A-Za-z]:\\\\"; then
      echo "WARN: $file:$line_no: Windows path detected:"
      echo "      $line"
      warned=1
    fi

    # Unix/WSL absolute paths
    if [ "$warned" -eq 0 ] && printf "%s\n" "$line" | grep -qE "(/mnt/|/home/|/Users/|/root/)"; then
      echo "WARN: $file:$line_no: absolute path detected:"
      echo "      $line"
      warned=1
    fi

    # Home-dir shorthand (but not in URLs)
    if [ "$warned" -eq 0 ] && printf "%s\n" "$line" | grep -E "~/" | grep -qv "http"; then
      echo "WARN: $file:$line_no: home-dir shorthand (~/) detected:"
      echo "      $line"
      warned=1
    fi

    # Relative filesystem paths (../ or ./) in list items
    if [ "$warned" -eq 0 ] && printf "%s\n" "$line" | grep -qE "^\s*-\s+.*\.\./|^\s*-\s+.*\.\/"; then
      echo "WARN: $file:$line_no: relative path detected:"
      echo "      $line"
      warned=1
    fi

    # Bare GitHub repo mention: `owner/repo` on lines without github.com
    if [ "$warned" -eq 0 ] && printf "%s\n" "$line" | grep -qE "\`[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\`" && ! printf "%s\n" "$line" | grep -q "github.com"; then
      echo "WARN: $file:$line_no: bare GitHub repo mention (consider adding https://github.com/...):"
      echo "      $line"
      warned=1
    fi

    if [ "$warned" -eq 1 ]; then
      found_any=1
    fi
  done < "$file"
done

if [ "$found_any" -eq 1 ]; then
  echo ""
  echo "Tip: if these paths are intentional, use: git commit --no-verify"
  exit 1
fi
exit 0
