# shellcheck shell=sh
# Open the menu automatically when logging in on the phone's own screen
# (not over SSH). Disable: touch ~/.no-auto-menu
if [ "$(tty 2>/dev/null)" = /dev/tty1 ] && [ -z "${GEMINI_MENU_SHOWN:-}" ] &&
   [ ! -e "$HOME/.no-auto-menu" ] && [ -x /usr/local/bin/menu ]; then
	export GEMINI_MENU_SHOWN=1
	/usr/local/bin/menu
fi
export PATH="$HOME/.local/bin:$PATH"
