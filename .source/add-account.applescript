-- "Add New Account": asks for a name, creates Accounts/<name>.nosync plus a "Claude (<name>)"
-- launcher next to this app, then opens Claude on that new, empty account so you can sign in.

use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use scripting additions

property dialogTitle : "Add New Claude Account"

on run
	set myPath to POSIX path of (path to me) -- ends in "/"
	set rootDir to (current application's NSString's stringWithString:myPath)'s stringByDeletingLastPathComponent() as text
	set tool to myPath & "Contents/Resources/make-launcher.sh"
	set myIcon to ((myPath & "Contents/Resources/applet.icns") as POSIX file) as alias

	if (current application's NSWorkspace's sharedWorkspace()'s URLForApplicationWithBundleIdentifier:"com.anthropic.claudefordesktop") is missing value then
		display alert "Claude isn't installed" message "Install the Claude app from claude.ai/download first." as critical
		return
	end if

	-- 1. Name
	set profileName to "Personal"
	repeat
		set answer to display dialog "What should this account be called?" & return & return & "You'll get a “Claude (name)” launcher in this folder that always opens this account." default answer profileName with title dialogTitle with icon myIcon buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel"
		set profileName to my trim(text returned of answer)
		try
			-- "new:<name>", or "existing:<name>" if that account's folder is here but its launcher was deleted
			set checked to do shell script "/bin/zsh " & quoted form of tool & " " & quoted form of rootDir & " --check " & quoted form of profileName
			set isExisting to checked starts with "existing:"
			set profileName to text ((offset of ":" in checked) + 1) thru -1 of checked
			if not isExisting then exit repeat
			set choice to button returned of (display dialog "There's already a “" & profileName & "” account in this folder, but its launcher is missing." & return & return & "Recreate the launcher for it? The account and its login stay as they are." with title dialogTitle with icon myIcon buttons {"Pick Another Name", "Recreate Launcher"} default button "Recreate Launcher")
			if choice is "Recreate Launcher" then exit repeat
		on error errMsg number errNum
			if errNum is -128 then error number -128
			display alert "Please choose another name" message errMsg as warning
		end try
	end repeat

	-- 2. Sign-in links (claude://...) go to whichever Claude window macOS picks, so the
	--    first sign-in only works reliably when no other Claude is open.
	if not isExisting and my claudePIDs() is not {} then
		set choice to button returned of (display dialog "Claude is open right now. Please quit it while you sign in to the new account, or the sign-in may finish in the wrong Claude window." & return & return & "You can reopen it as soon as you're signed in." with title dialogTitle with icon caution buttons {"Cancel", "Keep It Open", "Quit Claude"} default button "Quit Claude" cancel button "Cancel")
		if choice is "Quit Claude" then my quitClaude()
	end if

	-- 3. Create the account folder and launcher
	try
		set launcherPath to do shell script "/bin/zsh " & quoted form of tool & " " & quoted form of rootDir & " " & quoted form of profileName
		do shell script "/bin/zsh " & quoted form of tool & " " & quoted form of rootDir & " --default"
	on error errMsg
		display alert "Couldn't create the account" message errMsg as critical
		return
	end try

	-- 4. Open it
	if isExisting then
		display dialog "“Claude (" & profileName & ")” is back. Double-click it to open this account." with title dialogTitle with icon myIcon buttons {"Done", "Open Claude"} default button "Open Claude" cancel button "Done"
		do shell script "/usr/bin/open " & quoted form of launcherPath
		return
	end if
	display dialog "“Claude (" & profileName & ")” is ready." & return & return & "A new Claude window opens now: sign in there with your other account." & return & return & "Afterwards, double-click “Claude (" & profileName & ")” to open this account, and “Claude (Default)” to open your usual one, even while the other is running." with title dialogTitle with icon myIcon buttons {"Open Claude"} default button "Open Claude"
	do shell script "/usr/bin/open " & quoted form of launcherPath
end run

-- PIDs of all running Claude main processes (any account).
on claudePIDs()
	set apps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:"com.anthropic.claudefordesktop"
	return (apps's valueForKey:"processIdentifier") as list
end claudePIDs

on quitClaude()
	repeat
		set apps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:"com.anthropic.claudefordesktop"
		repeat with runningApp in (apps as list)
			runningApp's terminate()
		end repeat
		-- Give it up to 30 s (it may ask you to confirm first).
		repeat 60 times
			if my claudePIDs() is {} then return
			delay 0.5
		end repeat
		set choice to button returned of (display dialog "Claude is still open; it may be waiting for you to confirm." & return & return & "Quit it (⌘Q), then click Continue." with title dialogTitle with icon caution buttons {"Cancel", "Try Again", "Continue"} default button "Continue" cancel button "Cancel")
		if choice is "Continue" then return
	end repeat
end quitClaude

on trim(t)
	return ((current application's NSString's stringWithString:t)'s stringByTrimmingCharactersInSet:(current application's NSCharacterSet's whitespaceAndNewlineCharacterSet())) as text
end trim
