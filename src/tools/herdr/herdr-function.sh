# shellcheck shell=bash
# devbot-managed herdr wrapper, rendered into ~/.bashrc and ~/.zshrc by the
# herdr module. Edited here, never in the shell rc: every install and update
# replaces the block this file renders.
herdr() {
    # only a TUI launch needs the stack up
    local launch=no
    case "${1:-}" in
        ""|--session*|--remote*) launch=yes ;;
        session) [ "${2:-}" = attach ] && launch=yes ;;
    esac
    if [ "$launch" = yes ] && command -v devbot >/dev/null 2>&1; then
        # $$ is this shell's pid: it outlives `devbot up` and is the identity
        # the release below uses, so up and down name the same owner claim.
        if devbot up --owner herdr --owner-pid $$ 1>&2; then
            command herdr "$@"
            local herdr_rc=$?
            devbot down --owner herdr --owner-pid $$ 1>&2 || true
            return "${herdr_rc}"
        fi
        echo "herdr: devbot up failed — starting anyway" >&2
    fi
    command herdr "$@"
}
