#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#zsh nixpkgs#zsh-defer nixpkgs#zsh-nix-shell nixpkgs#zsh-fast-syntax-highlighting nixpkgs#zsh-autosuggestions nixpkgs#oh-my-zsh nixpkgs#zsh-history-substring-search nixpkgs#eza nixpkgs#comma --command bash
# Author: Collin Dewey
# Description:
# Configures ZSH
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
nix_shell_guard

echo "
autoload -Uz promptinit
promptinit
prompt suse
setopt histignorealldups sharehistory
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history
source \"$(nix path-info nixpkgs#zsh-defer)/share/zsh-defer/zsh-defer.plugin.zsh\";
zsh-defer source \"$(nix path-info nixpkgs#zsh-nix-shell)/share/zsh-nix-shell/nix-shell.plugin.zsh\";
zsh-defer source \"$(nix path-info nixpkgs#zsh-fast-syntax-highlighting)/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh\";
zsh-defer source \"$(nix path-info nixpkgs#zsh-history-substring-search)/share/zsh-history-substring-search/zsh-history-substring-search.zsh\";
zsh-defer source \"$(nix path-info nixpkgs#oh-my-zsh)/share/oh-my-zsh/plugins/sudo/sudo.plugin.zsh\";
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
alias ls=\"$(which eza)\"
alias ll=\"$(which eza) -l\"
. /opt/ccdc/helper.sh # Hardcoded. It shouldn't be. But it is.
alias update,=\"mkdir -p ~/.cache/nix-index; download https://github.com/Mic92/nix-index-database/releases/latest/download/index-x86_64-linux ~/.cache/nix-index/files; chown -R \"\$UID\" ~/.cache/nix-index\"
alias ,=\"web $(which ,)\"
RPROMPT='%F{white}[%*]%f'

# From https://wiki.archlinux.org/title/Zsh#Key_bindings
typeset -g -A key

bindkey -- \"\${terminfo[khome]}\"   beginning-of-line
bindkey -- \"\${terminfo[kend]}\"    end-of-line
bindkey -- \"\${terminfo[kich1]}\"   overwrite-mode
bindkey -- \"\${terminfo[kbs]}\"     backward-delete-char
bindkey -- \"\${terminfo[kdch1]}\"   delete-char
#bindkey -- \"\${terminfo[kcuu1]}\"  up-line-or-history
bindkey -- \"\${terminfo[kcuu1]}\"   history-substring-search-up
#bindkey -- \"\${terminfo[kcud1]}\"  down-line-or-history
bindkey -- \"\${terminfo[kcud1]}\"   history-substring-search-down
bindkey -- \"\${terminfo[kcub1]}\"   backward-char
bindkey -- \"\${terminfo[kcuf1]}\"   forward-char
bindkey -- \"\${terminfo[kpp]}\"     beginning-of-buffer-or-history
bindkey -- \"\${terminfo[knp]}\"     end-of-buffer-or-history
bindkey -- \"\${terminfo[kcbt]}\"    reverse-menu-complete
" > ~/.zshrc
cp ~/.zshrc /opt/ccdc/.zshrc

if command -v sudo &> /dev/null; then
  if [ -f /bin/zsh ]; then
    sudo mv /bin/zsh /bin/zsh_
  fi
  sudo ln -s $(which zsh) /bin/zsh
else
  if [ -f /bin/zsh ]; then
    su -c "mv /bin/zsh /bin/zsh_"
  fi
  su -c "ln -s $(which zsh) /bin/zsh"
fi

echo "Run zsh"