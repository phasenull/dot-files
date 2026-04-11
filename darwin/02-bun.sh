
if command -v brew &>/dev/null; then
  echo "[✔︎] bun already installed, updating..."
  bun upgrade
else
    echo "[...] Installing bun"
    curl -fsSL https://bun.sh/install | bash
fi