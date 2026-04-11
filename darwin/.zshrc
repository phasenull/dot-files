export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="/opt/homebrew/opt/node@28/bin:$PATH"
PS1='%{%F{green}%}%n%{%f%}%{%F{white}%}@%{%f%}%{%F{blue}%}%m%{%f%}% :%{%F{cyan}%}%1~%{%f%}% $ '
alias code="/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code"
alias discord="/Applications/Discord.app/Contents/MacOS/Discord"
export C_INCLUDE_PATH=$C_INCLUDE_PATH:/opt/homebrew/include
export LIBRARY_PATH=$LIBRARY_PATH:/opt/homebrew/lib
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.local/bin:$PATH"
alias wingcc='x86_64-w64-mingw32-gcc'

# bun completions
[ -s "~/.bun/_bun" ] && source "~/.bun/_bun"