# sh_terminator: see .zshenv. The last startup file of a login shell.
ZDOTDIR=$_sht_user_zdotdir
[[ -r $ZDOTDIR/.zlogin ]] && source $ZDOTDIR/.zlogin
(( $+functions[_sht_finish] )) && _sht_finish
