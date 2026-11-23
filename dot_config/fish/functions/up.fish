function up --description 'Update system and check maintenance (topgrade-style)'
    set -l start (date +%s)
    set -g _up_names
    set -g _up_status

    # Message helpers, styled after topgrade
    # https://github.com/topgrade-rs/topgrade

    function _up_rule -a color msg
        if test (count $msg) -gt 0
            set -l len (string length -- "$msg")
            set -l pad (math "30 - $len")
            test $pad -lt 1; and set pad 1
            echo (set_color $color)"── "$msg" "(string repeat --max $pad '─')(set_color normal)
        else
            echo (set_color $color)(string repeat --max 30 '─')(set_color normal)
        end
    end

    function _up_next -a color name
        if set -q _up_started
            echo
        end
        set -g _up_started 1
        _up_rule $color $name
    end

    function _up_mark -a color sym msg
        echo (set_color $color)"  $sym"(set_color normal)" $msg"
    end

    function _up_ok -a msg
        _up_mark green ✓ $msg
    end

    function _up_warn -a msg
        _up_mark yellow ! $msg
    end

    function _up_fail -a msg
        _up_mark red ✗ $msg >&2
    end

    function _up_item -a msg
        echo "    "$msg
    end

    function _up_track -a name state
        set -a _up_names $name
        set -a _up_status $state
    end

    # Privilege elevation command, same detection order as cachy-update
    set -l su_cmd
    for c in sudo sudo-rs doas run0
        command -q $c; and set su_cmd $c; and break
    end
    if test -z "$su_cmd"
        set su_cmd sudo
    end

    # Detect AUR helper (paru > yay > pikaur > pacman)
    set -l helper
    for h in paru yay pikaur
        command -q $h; and set helper $h; and break
    end

    _up_next cyan Packages
    if test -n "$helper"
        if $helper -Syu --noconfirm
            _up_ok "Packages updated ($helper)"
            _up_track Packages OK
        else
            _up_fail 'Package update failed'
            _up_track Packages FAILED
        end
    else if command -q pacman
        _up_warn 'No AUR helper found, updating with pacman'
        if $su_cmd pacman -Syu --noconfirm
            _up_ok 'Packages updated'
            _up_track Packages OK
        else
            _up_fail 'Package update failed'
            _up_track Packages FAILED
        end
    else
        _up_fail 'No supported package manager found'
        _up_track Packages FAILED
    end

    if command -q flatpak
        _up_next blue Flatpak
        if flatpak update -y
            _up_ok 'Flatpaks updated'
            _up_track Flatpak OK
        else
            _up_fail 'Flatpak update failed'
            _up_track Flatpak FAILED
        end
    else
        _up_track Flatpak SKIPPED
    end

    _up_next red 'Orphan packages'
    set -l orphans (pacman -Qtdq 2>/dev/null)
    if test (count $orphans) -gt 0
        _up_warn (count $orphans)' orphan package(s) found'
        for p in $orphans
            _up_item $p
        end
        if $su_cmd pacman --noconfirm -Rns $orphans
            _up_ok 'Orphan packages removed'
            _up_track Orphans OK
        else
            _up_fail 'Orphan removal failed'
            _up_track Orphans FAILED
        end
    else
        _up_ok 'No orphan packages found'
        _up_track Orphans OK
    end

    _up_next red 'Package cache'
    if command -q paccache
        set -l old (paccache -dk3 2>/dev/null | grep -oE '[0-9]+ candidates?' | grep -oE '[0-9]+' | head -1)
        set -l uninst (paccache -duk0 2>/dev/null | grep -oE '[0-9]+ candidates?' | grep -oE '[0-9]+' | head -1)
        set -l oldnum 0
        set -l uninstnum 0
        if test -n "$old"; set oldnum $old; end
        if test -n "$uninst"; set uninstnum $uninst; end
        if test (math "$oldnum + $uninstnum") -gt 0
            _up_warn (math "$oldnum + $uninstnum")' cached package(s) can be pruned'
            set -l failed 0
            if test $oldnum -gt 0
                $su_cmd paccache -rk3 > /dev/null; or set failed 1
            end
            if test $uninstnum -gt 0
                $su_cmd paccache -ruk0 > /dev/null; or set failed 1
            end
            if test $failed -eq 0
                _up_ok 'Package cache pruned'
                _up_track Cache OK
            else
                _up_fail 'Cache prune failed'
                _up_track Cache FAILED
            end
        else
            _up_ok 'No cached packages to prune'
            _up_track Cache OK
        end
    else
        _up_track Cache SKIPPED
    end

    _up_next yellow 'Kernel reboot'
    if systemd-detect-virt --container --quiet > /dev/null 2>&1
        _up_track Kernel SKIPPED
    else if pacman -Q kernel-modules-hook mkmm > /dev/null 2>&1
        _up_track Kernel SKIPPED
    else if test -f "/usr/lib/modules/"(uname -r)"/vmlinuz"
        _up_ok 'Running kernel is installed'
        _up_track Kernel OK
    else
        _up_warn 'Pending kernel update — reboot required to apply it'
        read -l -P (set_color cyan)"  ?"(set_color normal)" Reboot now? "(set_color green)"[Y/n]"(set_color normal)" " answer
        if string match -qr '^([yY]|$)' -- "$answer"
            if systemctl reboot
                _up_track Kernel OK
            else
                _up_fail 'Reboot failed'
                _up_track Kernel FAILED
            end
        else
            _up_track Kernel SKIPPED
        end
    end

    if command -q flatpak
        _up_next blue 'Flatpak unused'
        set -l unused (flatpak uninstall --unused < /dev/null 2>/dev/null | sed -n '/^ 1./,$p' | awk '{print $2}' | grep -v '^$' | sed '$d')
        if test (count $unused) -gt 0
            _up_warn (count $unused)' unused Flatpak package(s) found'
            for u in $unused
                _up_item $u
            end
            if flatpak uninstall --unused -y > /dev/null
                _up_ok 'Unused Flatpak packages removed'
                _up_track 'Flatpak unused' OK
            else
                _up_fail 'Flatpak cleanup failed'
                _up_track 'Flatpak unused' FAILED
            end
        else
            _up_ok 'No unused Flatpak packages'
            _up_track 'Flatpak unused' OK
        end
    else
        _up_track 'Flatpak unused' SKIPPED
    end

    if command -q checkservices
        _up_next yellow 'Service restart'
        set -l svcs ($su_cmd checkservices -F -P -R -i gdm.service -i plasmalogin.service -i sddm.service -i lightdm.service -i lxdm.service -i slim.service -i xdm.service -i greetd.service -i nodm.service -i ly.service -i lemurs.service 2>/dev/null | grep '.service' | cut -f2 -d "'")
        if test (count $svcs) -gt 0
            _up_warn (count $svcs)' service(s) need a restart after the upgrade'
            for s in $svcs
                _up_item $s
            end
            if $su_cmd systemctl restart $svcs
                _up_ok 'Services restarted'
                _up_track 'Service restart' OK
            else
                _up_fail 'Service restart failed'
                _up_track 'Service restart' FAILED
            end
        else
            _up_ok 'No services need a restart'
            _up_track 'Service restart' OK
        end
    else
        _up_track 'Service restart' SKIPPED
    end

    _up_next magenta 'Configuration files'
    set -l pacnew (find /etc -type f \
        \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null)

    if test (count $pacnew) -gt 0
        _up_warn (count $pacnew)" file(s) need attention (sudo pacdiff)"
        _up_item $pacnew
        _up_track Configuration WARNED
    else
        _up_ok 'No .pacnew or .pacsave files found'
        _up_track Configuration OK
    end

    if command -q systemctl
        _up_next yellow 'Systemd services'
        if systemctl --failed --plain --no-legend | string length -q
            _up_fail 'Failed services detected:'
            systemctl --failed
            _up_track Services FAILED
        else
            _up_ok 'All services are running normally'
            _up_track Services OK
        end
    else
        _up_track Services SKIPPED
    end

    # Summary
    set -l elapsed (math (date +%s) - $start)'s'
    _up_next green "Summary ($elapsed)"
    for i in (seq (count $_up_names))
        switch $_up_status[$i]
            case OK
                _up_mark green ✓ $_up_names[$i]
            case FAILED
                _up_mark red ✗ $_up_names[$i]
            case WARNED
                _up_mark yellow ! $_up_names[$i]
            case SKIPPED
                _up_mark brblack · $_up_names[$i]
        end
    end

    functions -e _up_rule _up_next _up_mark \
        _up_ok _up_warn _up_fail _up_item _up_track
    set -e _up_names _up_status _up_started
end
