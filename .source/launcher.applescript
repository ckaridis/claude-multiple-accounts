-- Opens one Claude account (profile), or brings it to the front if it's already open.
--
-- The same script is used for every launcher. make-launcher.sh writes the account into
-- the launcher's Info.plist:
--   ClaudeProfileName    e.g. "Personal"     (missing = your normal/default Claude account)
--   ClaudeProfileFolder  absolute path of Accounts/<name>.nosync when the launcher was made
--   ClaudeProfileRoot    the folder the launcher was made in

use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use scripting additions

property claudeBundleID : "com.anthropic.claudefordesktop"

on run
	set info to current application's NSBundle's mainBundle()
	set profileName to info's objectForInfoDictionaryKey:"ClaudeProfileName"

	set claudeApp to my findClaudeApp()
	if claudeApp is missing value then
		display alert "Claude isn't installed" message "Couldn't find the Claude app. Install it from claude.ai/download, then try again." as critical
		return
	end if

	if profileName is missing value then
		-- Your normal account: Claude started with no --user-data-dir.
		if my bringToFront(my findInstance("")) then return
		do shell script "/usr/bin/open -n -a " & quoted form of claudeApp
		return
	end if

	set profileName to profileName as text
	set profileDir to my profileFolder(info, profileName)
	if profileDir is missing value then
		set savedDir to info's objectForInfoDictionaryKey:"ClaudeProfileFolder"
		display alert "Can't find the “" & profileName & "” account" message "This launcher looks for its account in" & return & (savedDir as text) & return & "and in an Accounts folder next to itself." & return & return & "If you moved the folder that holds your Claude accounts, open this account with the “Claude (" & profileName & ")” launcher inside that folder." as critical
		return
	end if

	if my bringToFront(my findInstance(profileName)) then return
	-- -n starts a separate Claude process. --user-data-dir keeps this account's login and
	-- settings in its own folder; CLAUDE_CONFIG_DIR does the same for the Code tab (~/.claude).
	do shell script "/usr/bin/open -n -a " & quoted form of claudeApp & ¬
		" --env " & quoted form of ("CLAUDE_CONFIG_DIR=" & profileDir & "/claude-code") & ¬
		" --args " & quoted form of ("--user-data-dir=" & profileDir & "/app-data")
end run

-- The normal install in Applications; otherwise whichever copy macOS knows about.
on findClaudeApp()
	if (current application's NSFileManager's defaultManager()'s fileExistsAtPath:"/Applications/Claude.app") as boolean then return "/Applications/Claude.app"
	set appURL to current application's NSWorkspace's sharedWorkspace()'s URLForApplicationWithBundleIdentifier:claudeBundleID
	if appURL is missing value then return missing value
	return (appURL's |path|()) as text
end findClaudeApp

-- Where this account's data lives. Normally that's the path saved when the launcher was made.
-- If the launcher is no longer in that folder, either the whole folder was moved (look next to
-- the launcher) or only the launcher was copied, e.g. into Applications (use the saved path).
-- Only then do we touch the disk, so normal launches never trigger a Desktop-folder prompt.
on profileFolder(info, profileName)
	set savedDir to info's objectForInfoDictionaryKey:"ClaudeProfileFolder"
	set savedRoot to info's objectForInfoDictionaryKey:"ClaudeProfileRoot"
	set myDir to (info's bundlePath()'s stringByDeletingLastPathComponent()) as text
	if savedRoot is not missing value and (savedRoot as text) is myDir then return savedDir as text

	set candidates to {myDir & "/Accounts/" & profileName & ".nosync"}
	if savedDir is not missing value then set end of candidates to savedDir as text
	repeat with candidateRef in candidates
		set candidate to contents of candidateRef
		try
			return do shell script "/bin/test -d " & quoted form of (candidate & "/app-data") & " && /bin/realpath " & quoted form of candidate
		end try
	end repeat
	return missing value
end profileFolder

-- PID of this account's running Claude, or 0. profileName "" means your normal account
-- (a Claude without --user-data-dir).
-- Claude has no single-instance lock, so we must check this ourselves: two Claude processes on
-- the same folder can corrupt it. Only your own Claude apps are considered (whichever copy of
-- Claude.app they run from), and an account is recognised by the end of its folder path,
-- ".../Accounts/<name>.nosync/app-data", so it's still found after the folder was moved or
-- renamed while it was open.
on findInstance(profileName)
	set wanted to "/Accounts/" & profileName & ".nosync/app-data "
	set apps to current application's NSRunningApplication's runningApplicationsWithBundleIdentifier:claudeBundleID
	repeat with runningApp in (apps as list)
		set pid to (runningApp's processIdentifier()) as integer
		try
			set cmd to (do shell script "/bin/ps -p " & pid & " -wwo command=") & " "
			if profileName is "" then
				if cmd does not contain " --user-data-dir=" then return pid
			else if cmd contains wanted then
				return pid
			end if
		end try
	end repeat
	return 0
end findInstance

-- Brings Claude process pid to the front. False if it isn't running (pid 0 or it just quit).
on bringToFront(pid)
	if pid is 0 then return false
	set runningApp to current application's NSRunningApplication's runningApplicationWithProcessIdentifier:pid
	if runningApp is missing value then return false
	-- A "reopen" event is what clicking an app's Dock icon sends; Claude uses it to recreate
	-- its window if you had closed it. Plain activation would show no window in that case.
	try
		set targetDesc to current application's NSAppleEventDescriptor's descriptorWithProcessIdentifier:pid
		-- 1634039412 = 'aevt' (core events), 1918988400 = 'rapp' (reopen application)
		set reopenEvent to current application's NSAppleEventDescriptor's appleEventWithEventClass:1634039412 eventID:1918988400 targetDescriptor:targetDesc returnID:-1 transactionID:0
		reopenEvent's sendEventWithOptions:1 |timeout|:5 |error|:(reference)
	end try
	runningApp's unhide()
	-- Since macOS 14 the active app (this launcher, after your double-click) has to hand focus over.
	try
		current application's NSApplication's sharedApplication()'s yieldActivationToApplication:runningApp
	end try
	runningApp's activateWithOptions:(current application's NSApplicationActivateAllWindows)
	return true
end bringToFront
