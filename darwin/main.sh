
[[ "$OSTYPE" == darwin* ]] || exit 0
cp .zshrc ~/
echo "[✔︎] Copied .zshrc to ~/"
source ~/.zshrc

sh ./01-brew.sh
# sh ./02-bun.sh



