source /usr/share/cachyos-fish-config/cachyos-config.fish

# Abbreviations
abbr wt curl wttr.in/Monastir
abbr ve pacman -Qs
abbr ff fastfetch
abbr se paru -Ss
abbr in sudo pacman -Sy
abbr ins paru -Sy --noconfirm
abbr rem sudo pacman -Runs
abbr gpu sudo intel_gpu_top
abbr bl sudo systemctl restart bluetooth
abbr mic sudo micro
abbr mi micro
abbr e exit
abbr fi flatpak install
abbr fu flatpak uninstall

# Use fd as the default fzf command
set -x FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'

# ante
fish_add_path "$HOME/.ante/bin"

if ~/.local/bin/term-is-dark 2>/dev/null
    set -e fish_color_autosuggestion; set -g fish_color_autosuggestion b0b0b0
    set -e fish_color_command; set -g fish_color_command 5fff00
    set -e fish_color_param; set -g fish_color_param d7d7d7
    set -e fish_color_comment; set -g fish_color_comment 5fd7ff
    set -e fish_color_error; set -g fish_color_error ff5555
    set -e fish_color_quote; set -g fish_color_quote ff5555
else
    set -e fish_color_autosuggestion; set -g fish_color_autosuggestion 555
    set -e fish_color_command; set -g fish_color_command 00a000
    set -e fish_color_param; set -g fish_color_param 323232
    set -e fish_color_comment; set -g fish_color_comment 6c6c6c
    set -e fish_color_error; set -g fish_color_error ff0000
    set -e fish_color_quote; set -g fish_color_quote ff0000
end

function __gnome_theme_autosync --on-event fish_postexec
    set -l want_suggest; set -l want_command; set -l want_param
    set -l want_comment; set -l want_error; set -l want_quote
    if ~/.local/bin/term-is-dark 2>/dev/null
        set want_suggest b0b0b0; set want_command 5fff00; set want_param d7d7d7
        set want_comment 5fd7ff; set want_error ff5555; set want_quote ff5555
    else
        set want_suggest 555; set want_command 00a000; set want_param 323232
        set want_comment 6c6c6c; set want_error ff0000; set want_quote ff0000
    end
    if test "$fish_color_autosuggestion" != "$want_suggest"
        set -g fish_color_autosuggestion $want_suggest
        set -g fish_color_command $want_command
        set -g fish_color_param $want_param
        set -g fish_color_comment $want_comment
        set -g fish_color_error $want_error
        set -g fish_color_quote $want_quote
    end
end

# chezmoi completions (generated dynamically, not tracked)
if status is-interactive; and command -q chezmoi
    chezmoi completion fish | source
end
