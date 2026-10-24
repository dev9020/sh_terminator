# sh_terminator: see .zshenv.

# macOS's /etc/zshrc, run just before this file, set HISTFILE from ZDOTDIR,
# which was this directory then: put the history back where it belongs
# (the user's .zshrc can still set its own below).
[[ $HISTFILE == $_sht_dir/.zsh_history ]] && HISTFILE=$_sht_user_zdotdir/.zsh_history

ZDOTDIR=$_sht_user_zdotdir
[[ -r $ZDOTDIR/.zshrc ]] && source $ZDOTDIR/.zshrc
_sht_user_zdotdir=$ZDOTDIR
ZDOTDIR=$_sht_dir

# Hands ZDOTDIR back to the user, so shells started from this one (and
# anything reading ZDOTDIR) see their setup, not this directory.
_sht_finish() {
  if [[ $_sht_user_zdotdir == $HOME ]]; then
    unset ZDOTDIR
  else
    ZDOTDIR=$_sht_user_zdotdir
  fi
  unset _sht_user_zdotdir
  unfunction _sht_finish
}

# The wrappers, defined after the user's .zshrc so they win over its
# functions; an alias such as `curl='curl -s'` still ends up in them.
# Before each run a wrapper checks whether the app's proxy settings file
# changed (a stat, nothing more) and only then asks the app for the proxy
# in use; so a proxy added, changed or turned off in the app applies to
# the next command here. `command env … curl` runs the real program with
# the proxy in its environment only.
if [[ -n $_sht_dir && -n $_sht_app && -n $_sht_config ]] && zmodload -F zsh/stat b:zstat 2>/dev/null; then
  _sht_stamp=unset
  _sht_tools=
  _sht_proxy=
  # ssh has no proxy variable: it runs this helper to reach the server
  # (see sht-socks5). The path is quoted for the shell ssh runs it with.
  _sht_ssh_proxy="ProxyCommand=/usr/bin/perl ${(q)_sht_dir}/sht-socks5 %h %p"

  _sht_refresh() {
    local -A st
    local stamp=none out=
    zstat -H st -- $_sht_config 2>/dev/null && stamp="$st[inode]:$st[mtime]"
    [[ $stamp == $_sht_stamp ]] && return 0
    if [[ $stamp != none ]]; then
      out=$(command "$_sht_app" --pane-proxy) || {
        print -u2 "sh_terminator: couldn't get the proxy from the app, so not running without it"
        return 1
      }
    fi
    _sht_stamp=$stamp
    _sht_tools=${${(f)out}[1]}
    _sht_proxy=${${(f)out}[2]}
  }

  # 0: through the proxy, 1: straight, 2: don't run at all (a proxy may be
  # wanted, but it's unknown which).
  _sht_route() {
    _sht_refresh || return 2
    [[ -n $_sht_proxy && " $_sht_tools " == *" $1 "* ]]
  }

  # curl, git (https remotes) and brew read these; set in every spelling
  # they check so a proxy already in the user's environment can't win.
  _sht_with_proxy() {
    command env all_proxy=$_sht_proxy ALL_PROXY=$_sht_proxy \
      https_proxy=$_sht_proxy HTTPS_PROXY=$_sht_proxy http_proxy=$_sht_proxy "$@"
  }

  curl() {
    _sht_route curl
    case $? in
      0) _sht_with_proxy curl "$@" ;;
      1) command curl "$@" ;;
      *) return 1 ;;
    esac
  }

  brew() {
    _sht_route brew
    case $? in
      0) _sht_with_proxy brew "$@" ;;
      1) command brew "$@" ;;
      *) return 1 ;;
    esac
  }

  # https remotes through the variables, ssh remotes through the helper,
  # on top of the user's own ssh command if they set one.
  git() {
    _sht_route git
    case $? in
      0)
        local ssh_command=${GIT_SSH_COMMAND:-$(command git config --get core.sshCommand 2>/dev/null)}
        _sht_with_proxy SHT_PROXY_URL=$_sht_proxy \
          GIT_SSH_COMMAND="${ssh_command:-ssh} -o ${(q)_sht_ssh_proxy}" git "$@"
        ;;
      1) command git "$@" ;;
      *) return 1 ;;
    esac
  }

  # ssh, scp and sftp follow the one "ssh" switch.
  _sht_ssh_family() {
    local program=$1
    shift
    _sht_route ssh
    case $? in
      0) command env SHT_PROXY_URL=$_sht_proxy $program -o $_sht_ssh_proxy "$@" ;;
      1) command $program "$@" ;;
      *) return 1 ;;
    esac
  }
  ssh() { _sht_ssh_family ssh "$@" }
  scp() { _sht_ssh_family scp "$@" }
  sftp() { _sht_ssh_family sftp "$@" }
fi

[[ -o login ]] || _sht_finish
