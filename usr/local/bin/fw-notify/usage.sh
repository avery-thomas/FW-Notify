#!/bin/bash

# Title: macOS Computer Usage (example)
# Author: Avery Thomas - FileWave
# Dependencies: "alerter" - https://github.com/vjeantet/alerter

############
# Variables
############

# What user in currently logged in? Do NOT change!
logged_in_user=$(stat -f '%Su' /dev/console)

# Determine full name of logged in user. Do NOT change!
full_name=$(finger $(whoami) | awk '/Name:/ {print $4" "$5}')

# Get launch arguments passed from FileWave
fw_server="$1"
token="$2"
device_id="$3"

# Alert Title
alert_title="Hello $full_name,"

# Alert Message
alert_message="What will you be using this computer for today (Email, Photoshop, etc.)?"

# Alert Icon File path
alert_icon="/usr/local/sbin/FileWave.app/Contents/Resources/fwGUI.app/Contents/Resources/kiosk.icns"

# Notification Time (default 120 sec)
notification_timeout="120"

###########################
# DO NOT MODIFY BELOW HERE
###########################
cd /usr/local/bin/fw-notify/

# Are any users logged in?
loggedon=$(who | grep console | wc -l)

date_f=$(date +%Y-%m-%d-%H:%M:%S)

# Log all to output FileWave Client Log
#exec 1>>/var/log/fwcld.log
#exec 2>>/var/log/fwcld.log

function plist_gen {
	/usr/libexec/PlistBuddy -c "Add :CurrentUsage string null" usage.plist
	/usr/libexec/PlistBuddy -c "Add :PreviousUsage array" usage.plist
	/usr/libexec/PlistBuddy -c "Add :DeviceID string $device_id" usage.plist
	/usr/libexec/PlistBuddy -c "Add :Token string $token" usage.plist
	/usr/libexec/PlistBuddy -c "Add :FWServer string $fw_server" usage.plist
}

function plist_update {
	# Pull FileWave Client variables from local file for future usage.
	token=$(/usr/libexec/PlistBuddy -c "Print :Token" usage.plist)
	device_id=$(/usr/libexec/PlistBuddy -c "Print :DeviceID" usage.plist)
	fw_server=$(/usr/libexec/PlistBuddy -c "Print :FWServer" usage.plist)

	# Write value locally for offline reporting
	/usr/libexec/PlistBuddy -c "Set :CurrentUsage '$1 | $2 | $3'" usage.plist

	# Write to API if online
	curl --silent --output /dev/null -X PATCH https://$fw_server:20445/inv/api/v1/client/$device_id -H "authorization: $token" -H "cache-control: no- cache" -H "content-type: application/json" -d "{\"stringfields\": {\"current_usage\": \"$1 | $2 | $3\"}}"
	
	# Trigger success notification
	success_notification "$1"
	exit 0
}

# Show Notification with options.
function initial_notification {
	NOTIFICATION=$(/usr/local/bin/fw-notify/alerter -reply -message "$alert_message" -title "$alert_title" -timeout $notification_timeout -appIcon "$alert_icon")
	case $NOTIFICATION in
		"@TIMEOUT") exit 1 ;;
    		"@CLOSED") initial_notification ;;
    		"@ACTIONCLICKED") initial_notification ;;
    		"@CONTENTCLICKED") initial_notification ;;
    		**) plist_update "$NOTIFICATION" "$logged_in_user" "$date_f" ;;
	esac
}

function success_notification {
	NOTIFICATION=$(/usr/local/bin/fw-notify/alerter -message "Your response \"$1\" has been submitted." -title "Thank you!" -timeout $notification_timeout -appIcon "$alert_icon")
	case $NOTIFICATION in
		"@TIMEOUT") exit 1 ;;
    		"@CLOSED") exit 1 ;;
    		"@ACTIONCLICKED") exit 1 ;;
    		"@CONTENTCLICKED") exit 1 ;;
    		**) echo "? --> $NOTIFICATION" ;;
	esac
}

if [ "$loggedon" -lt "1" ]; then
	echo "$(timestamp)No users logged in, suppressing prompt."
	exit 1
elif [ ! -f "usage.plist" ]; then
	plist_gen
	initial_notification
else
	previous_usage=$(/usr/libexec/PlistBuddy -c "Print :CurrentUsage" usage.plist)
	/usr/libexec/PlistBuddy -c "Add :PreviousUsage: string $previous_usage" usage.plist
	initial_notification
fi