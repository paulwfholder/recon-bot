#!/bin/bash
# recon-bot.sh - Bug Bounty Reconnaissance Tool
# Usage: ./recon-bot.sh [target_domain]

set -euo pipefail

# === 1. Setup ===
TARGET=${1:-"juice-shop.herokuapp.com"}
DATE=$(date +%Y-%m-%d_%H-%M-%S)
OUTPUT_DIR="recon-output/$TARGET/$DATE"
mkdir -p "$OUTPUT_DIR"
echo "[+] Starting recon on $TARGET (Output: $OUTPUT_DIR)"


# === 2. Host Discovery ===
echo "[+] Discovering live hosts..."
echo "$TARGET" > "$OUTPUT_DIR/hosts.txt"
httpx -l "$OUTPUT_DIR/hosts.txt" \
      -o "$OUTPUT_DIR/live.txt" \
      -status-code -title


# === 3. Screenshot Capture ===
echo "[+] Taking screenshots of live hosts..."
mkdir -p "$OUTPUT_DIR/screenshots"
if [ -f "$OUTPUT_DIR/live.txt" ]; then
  while IFS= read -r url || [ -n "$url" ]; do
    [ -z "$url" ] && continue
    filename=$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g')
    echo "[+] Screenshot: $url"
    if ! gowitness single "$url" \
        --destination "$OUTPUT_DIR/screenshots" \
        --output-filename "${filename}.png" 2>/dev/null; then
      echo "[!] Screenshot failed for $url"
    fi
  done < "$OUTPUT_DIR/live.txt"
else
  echo "[!] No live.txt file found"
fi
echo "[+] Screenshots saved in $OUTPUT_DIR/screenshots/ directory"


# === 4. Update & Validate Nuclei ===
echo "[+] Updating nuclei templates..."
nuclei -update-templates

echo "[+] Validating templates..."
nuclei -validate -t "$HOME/nuclei-templates" || echo "[!] Some templates failed validation"

# === 5. Vulnerability Scan (Nuclei) ===
echo "[+] Running nuclei scan (medium,high)..."
nuclei \
  -l "$OUTPUT_DIR/live.txt" \
  -t "$HOME/nuclei-templates" \
  -severity medium,high \
  -o "$OUTPUT_DIR/nuclei.txt"


# === 6. Directory Fuzzing (FFUF) ===
echo "[+] Running directory fuzz..."
ffuf -w /usr/share/wordlists/dirb/common.txt \
     -u "https://$TARGET/FUZZ" \
     -mc 200,301,302 \
     -o "$OUTPUT_DIR/ffuf.txt" \
  || echo "[!] ffuf failed"

# === 7. Generate Report ===
echo "[+] Generating markdown report..."
cat > "$OUTPUT_DIR/report.md" << EOF
# Recon Report: $TARGET
Date: $DATE

## Live Hosts
\`\`\`
$(cat "$OUTPUT_DIR/live.txt")
\`\`\`

## Vulnerabilities Found
\`\`\`
$(cat "$OUTPUT_DIR/nuclei.txt" 2>/dev/null || echo "No vulnerabilities found")
\`\`\`

## Directory Fuzzing Results
\`\`\`
$(cat "$OUTPUT_DIR/ffuf.txt" 2>/dev/null || echo "No directory fuzzing results")
\`\`\`
EOF

echo "[+] Recon complete! Report → $OUTPUT_DIR/report.md"
