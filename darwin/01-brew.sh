[[ "$OSTYPE" == darwin* ]] || exit 0
source ~/.zshrc


defaults write com.apple.dock autohide -bool true
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write NSGlobalDomain AppleLanguages -array "en-GB" "tr-TR"
defaults write NSGlobalDomain "AppleInterfaceStyle" Dark;

defaults write NSGlobalDomain "com.apple.keyboard.fnState" -int 1;
defaults write NSGlobalDomain "com.apple.mouse.linear" -int 1;
defaults write NSGlobalDomain "com.apple.mouse.scaling" -int 1;
defaults write NSGlobalDomain "com.apple.sound.beep.flash" -int 0;
defaults write NSGlobalDomain "com.apple.springing.delay" -float "0.5";
defaults write NSGlobalDomain "com.apple.springing.enabled" -int 1;
defaults write NSGlobalDomain "com.apple.swipescrolldirection" -int 1;
defaults write NSGlobalDomain "com.apple.trackpad.forceClick" -int 1;

mkdir ~/projects

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

if [-d /Applications/Discord.app ]; then
    echo "[✔︎] discord exists, skipped."
else
    echo "[...] Installing discord"
    brew install --cask discord
fi
if [-d /Applications/LinearMouse.app ]; then
    echo "[✔︎] linearmouse exists, skipped."
else
    echo "[...] Installing linearmouse"
    brew install --cask linearmouse
fi

if [ -d /Applications/iTerm.app ]; then
    echo "[✔︎] iterm2 exists, skipped."
else
    echo "[...] Installing iterm2"
    brew install --cask iterm2
fi