
source ~/.zshrc
if command -v brew &>/dev/null; then
  echo "[✔︎] brew already installed, updating..."
  brew update
else
    echo "[...] Installing brew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi


if command -v code &>/dev/null; then
    echo "[✔︎] code exists, skipped."
else
    echo "[...] Installing code"
    brew install --cask visual-studio-code
fi

if command -v discord &>/dev/null; then
    echo "[✔︎] discord exists, skipped."
else
    echo "[...] Installing discord"
    brew install --cask discord
fi
if command -v linearmouse &>/dev/null; then
    echo "[✔︎] linearmouse exists, skipped."
else
    echo "[...] Installing linearmouse"
    brew install --cask linearmouse
fi

if command -v iterm2 &>/dev/null; then
    echo "[✔︎] iterm2 exists, skipped."
else
    echo "[...] Installing iterm2"
    brew install --cask iterm2
fi