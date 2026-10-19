#!/bin/zsh
# Creates a Claude account folder and its double-clickable launcher.
#
#   make-launcher.sh <root> <Name>            create Accounts/<Name>.nosync and "Claude (<Name>).app"
#                                             (if only the launcher is missing, recreate just the launcher)
#   make-launcher.sh <root> --check <Name>    only check the name; prints "new:<Name>" or, when the account
#                                             folder exists without its launcher, "existing:<Name as on disk>"
#   make-launcher.sh <root> --default         create "Claude (Default).app" (your normal account) if missing
#   make-launcher.sh <root> --build           (re)build "Add New Account.app" from these sources, plus --default
#
# Exit codes: 1 = failed, 2 = invalid name, 3 = already exists. Prints the launcher path on success.
#
# Errors are checked explicitly (no `set -e`): zsh's errexit skips EXIT traps and `always` blocks
# when it fires inside a function, which would leave half-made accounts and temp folders behind.
set -u -o pipefail
export LC_ALL=C

HERE=${0:A:h}                       # launcher.applescript and make-icon.js live next to this script
ROOT=${1:?root folder}; ROOT=${ROOT:A}
shift

die() { print -u2 -r -- "$1"; exit "${2:-1}"; }

claude_app() {
  local p
  p=$(/usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); var u = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier("com.anthropic.claudefordesktop"); u.isNil() ? "" : u.path.js' 2>/dev/null)
  print -r -- "${p:-/Applications/Claude.app}"
}

# check_name <name>: exits 2/3 if the name can't be used. Otherwise sets $name to the spelling to use
# and $existing to 1 if Accounts/<name>.nosync is already there (its launcher was deleted).
check_name() {
  name=$1 existing=0
  [[ $name =~ '^[A-Za-z0-9]([A-Za-z0-9 _-]{0,28}[A-Za-z0-9])?$' ]] ||
    die "Use 1–30 characters: plain letters A–Z, digits, spaces, - or _ (starting and ending with a letter or digit)." 2
  [[ ${name:l} != default ]] ||
    die "“Default” is the name used for your normal Claude account. Pick another name." 2
  # The Mac's disk ignores upper/lower case, so "personal" also matches "Personal".
  [[ ! -e "$ROOT/Claude ($name).app" ]] ||
    die "There is already an account called “$name”." 3
  [[ -d "$ROOT/Accounts/$name.nosync" || ! -e "$ROOT/Accounts/$name.nosync" ]] ||
    die "Accounts/$name.nosync already exists and isn't a folder." 3
  local dir
  for dir in "$ROOT"/Accounts/*.nosync(N/); do
    if [[ ${dir:t:l} == "${name:l}.nosync" ]]; then
      name=${dir:t:r} existing=1
    fi
  done
}

# make_app <final .app path> <script> <badge label> <r,g,b> <bundle id> [<Info.plist key> <value>]...
# Builds in a temp folder and only then moves the app into place.
# Files listed in $extra_resources are copied into the app's Contents/Resources.
extra_resources=()
make_app() {
  local tmp rc
  tmp=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/claude-launcher.XXXXXX") || return 1
  build_app "$tmp" "$@"; rc=$?
  /bin/rm -rf "$tmp"
  return $rc
}

build_app() {
  local tmp=$1 app=$2 script=$3 label=$4 rgb=$5 bundle_id=$6; shift 6
  local built="$tmp/${app:t}"
  local plist="$built/Contents/Info.plist"
  local icns="$(claude_app)/Contents/Resources/electron.icns"

  # (osacompile signs the applet and says "replacing existing signature"; that's not an error.)
  /usr/bin/osacompile -o "$built" "$script" 2> >(/usr/bin/grep -v 'replacing existing signature' >&2) || return 1
  if (( ${#extra_resources} )); then
    /bin/cp "${extra_resources[@]}" "$built/Contents/Resources/" || return 1
  fi

  # Claude's icon with a name label. If that fails, the launcher keeps the standard script icon.
  if [[ -f $icns ]] &&
     /usr/bin/osascript -l JavaScript "$HERE/make-icon.js" "$icns" "$tmp/icon.iconset" "$label" "$rgb" >/dev/null &&
     /usr/bin/iconutil -c icns -o "$built/Contents/Resources/applet.icns" "$tmp/icon.iconset"; then
    # The asset catalog would override applet.icns on recent macOS.
    /bin/rm -f "$built/Contents/Resources/Assets.car"
    /usr/bin/plutil -remove CFBundleIconName "$plist" 2>/dev/null
  fi

  /usr/bin/plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist" || return 1
  while (( $# >= 2 )); do
    /usr/bin/plutil -replace "$1" -string "$2" "$plist" || return 1
    shift 2
  done
  # Drop extended attributes (e.g. quarantine flags copied from a downloaded ZIP, Finder info)
  # that codesign refuses, then re-sign: editing the bundle broke osacompile's signature.
  /usr/bin/xattr -cr "$built" 2>/dev/null
  /usr/bin/codesign --force --deep --sign - "$built" 2>/dev/null || return 1

  /bin/rm -rf "$app" && /bin/mv "$built" "$app" || return 1
  /usr/bin/touch "$app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" 2>/dev/null
  return 0
}

make_default() {
  local app="$ROOT/Claude (Default).app"
  if [[ ! -e $app ]]; then
    make_app "$app" "$HERE/launcher.applescript" "Default" "0.32,0.32,0.36" "local.claude-launcher.default" ||
      die "Couldn't create “Claude (Default)”."
  fi
  print -r -- "$app"
}

case ${1:-} in
  --check)
    check_name "${2-}"
    (( existing )) && print -r -- "existing:$name" || print -r -- "new:$name"
    ;;

  --default)
    make_default
    ;;

  --build)
    extra_resources=("$HERE/make-launcher.sh" "$HERE/launcher.applescript" "$HERE/make-icon.js")
    make_app "$ROOT/Add New Account.app" "$HERE/add-account.applescript" "+ Add" "0.13,0.58,0.32" "local.claude-launcher.add-account" ||
      die "Couldn't build “Add New Account”."
    extra_resources=()
    print -r -- "$ROOT/Add New Account.app"
    make_default
    ;;

  ""|-*)
    die "usage: ${0:t} <root> <Name> | --check <Name> | --default | --build" 64
    ;;

  *)
    check_name "$1"
    profile="$ROOT/Accounts/$name.nosync"
    app="$ROOT/Claude ($name).app"

    colors=(0.13,0.40,0.85 0.55,0.30,0.80 0.88,0.42,0.10 0.05,0.55,0.60 0.82,0.22,0.48 0.13,0.58,0.32)
    sum=$(print -rn -- "$name" | /usr/bin/cksum | /usr/bin/cut -d' ' -f1)
    rgb=${colors[$(( sum % ${#colors} + 1 ))]}
    slug=$(print -rn -- "${name:l}" | /usr/bin/tr -cs 'a-z0-9' '-')
    slug=${${slug#-}%-}

    if /bin/mkdir -p "$profile/app-data" "$profile/claude-code" && /bin/chmod 700 "$profile"; then
      # ".nosync" plus this attribute keep the account's data (logins, caches) out of iCloud Drive.
      /usr/bin/xattr -w 'com.apple.fileprovider.ignore#P' 1 "$profile" 2>/dev/null
      if make_app "$app" "$HERE/launcher.applescript" "$name" "$rgb" "local.claude-launcher.$slug.$(/bin/date +%s)" \
           ClaudeProfileName "$name" ClaudeProfileFolder "$profile" ClaudeProfileRoot "$ROOT"; then
        print -r -- "$app"
        exit 0
      fi
    fi
    # Remove the half-made account so the same name can be used again (never an existing one).
    (( existing )) || /bin/rm -rf "$profile"
    die "Couldn't create the account folder or launcher for “$name”."
    ;;
esac
