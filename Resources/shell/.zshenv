# sh_terminator: proxy for chosen programs in this pane.
#
# The app points ZDOTDIR here for every zsh pane (see ProxyStore). zsh then
# reads its startup files from this directory; each one runs the user's own
# file first, at top level and with ZDOTDIR set back to theirs, so their
# setup behaves as it would without the app. .zshrc adds the wrappers last.

# Kept in plain shell parameters, not the environment, so programs this
# shell starts don't inherit them.
_sht_dir=$SHT_SHELL_DIR
_sht_app=$SHT_APP
_sht_config=$SHT_PROXY_CONFIG
_sht_user_zdotdir=${SHT_USER_ZDOTDIR:-$HOME}
unset SHT_SHELL_DIR SHT_APP SHT_PROXY_CONFIG SHT_USER_ZDOTDIR

ZDOTDIR=$_sht_user_zdotdir
[[ -r $ZDOTDIR/.zshenv ]] && source $ZDOTDIR/.zshenv
_sht_user_zdotdir=$ZDOTDIR
ZDOTDIR=$_sht_dir
