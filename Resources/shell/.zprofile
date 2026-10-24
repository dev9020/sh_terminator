# sh_terminator: see .zshenv.
ZDOTDIR=$_sht_user_zdotdir
[[ -r $ZDOTDIR/.zprofile ]] && source $ZDOTDIR/.zprofile
_sht_user_zdotdir=$ZDOTDIR
ZDOTDIR=$_sht_dir
