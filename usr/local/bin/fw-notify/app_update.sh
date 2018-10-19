#!/bin/bash

# Title: macOS App Update Notifier
# Author: Avery Thomas - FileWave
# Dependencies: "alerter" - https://github.com/vjeantet/alerter

############
# Variables
############

# Application name - Do NOT change (passed from script)
application="$1"

# "Try Tonight" timer (default 18:00hrs)
tonight_time="18"

# "Try Tomorrow" timer (default 8:00hrs)
tomorrow_time="8"

# Notification Time (default 120 sec)
notification_timeout="120"

# "Try in X hour(s)" timer
hour_timer="1"

# Force timer in days
force_timer="2"

# Main Alert Title
start_title="Update Required: $application"

# Main Alert Message
start_message="$application will automatically Quit and update upon 'Install'."

# Completion Alert Title
complete_title="Update Complete: $application"

# Completion Alert Message
complete_message="You may now re-open $application."

# Force Message
force_message="$application will automatically Quit within $notification_timeout seconds."

# Alert Icon File path
alert_icon="/usr/local/sbin/FileWave.app/Contents/Resources/fwGUI.app/Contents/Resources/kiosk.icns"

###########################
# DO NOT MODIFY BELOW HERE
###########################
cd /usr/local/bin/fw-notify/

# Log all to output FileWave Client Log
exec 1>>/var/log/fwcld.log
exec 2>>/var/log/fwcld.log

# Timer value formatted to seconds.
hour_timer_s=$((hour_timer * 60 * 60))

# Force timer value formatted to seconds.
force_timer_s=$((force_timer * 60 * 60 * 24))

# Application PID
pid=$(ps -xa | grep -i "$application.app" | grep -v grep | awk {'print $1'})

# Are any users logged in?
loggedon=$(who | grep console | wc -l)

# What user in currently logged in?
logged_in_user=$(stat -f '%Su' /dev/console)

# Date in seconds (for "hour" calculation)
function CURR_DATE_SEC {
	echo "$(date +%s)"
}

# Hour of date (for "try tonight" calculation) 
function CURR_DATE_HOUR {
	echo "$(date +%H)"
}

# Timestamp function for logging
function timestamp {
	echo "$(date +%Y-%m-%d\ %H:%M:%S)|fw-notify|Update Notifer|$application|"
}

# Requirements for script. No user logged in? App not running, exit 0.
function start_reqs {
	if [ "$loggedon" -lt "1" ] || [ -z "$pid" ]; then
		if [ "$loggedon" -lt "1" ]; then
			echo "$(timestamp)No users logged in, installing update."
			exit 0
		elif [ -z "$pid" ]; then
			echo "$(timestamp)Application not running, installing update."
			exit 0
		fi
	reset_timer
	fi
}

function complete_reqs {
	if [ "$loggedon" -lt "1" ]; then
		echo "$(timestamp)No users logged in, installing update."
		reset_timer	
		exit 0
	fi
}

# Reset timer upon successful activation of Fileset
function reset_timer {
	#/usr/libexec/PlistBuddy -c "Set :TimerType 0" "$application.plist"
	#echo "$(timestamp)Reset timer for future $application update notifications."
	#/usr/libexec/PlistBuddy -c "Set :StartDate 0" "$application.plist"
	#echo "$(timestamp)Reset force timer for future $application update notifications."
	rm -rf "$application.plist"
}

# If timeout met, default to notifying at hourly rate.
function timeout {
	echo "$(timestamp)'$logged_in_user' did not acknowledge notification within $notification_timeout seconds."
	timer hour
}

# Re-open application, reset timer, exit 0, and complete installation.
function open_app {
	su - "$logged_in_user" -c "open -a '$application'"
	echo "$(timestamp)'$logged_in_user' re-opened $application after update using notification."
}

# Timer function to determine settings either "hour", "try tonight ", or "try tomorrow".
function timer {
	if [ "$1" == "hour" ]; then
		/usr/libexec/PlistBuddy -c "Set :TimerType 1" "$application.plist"
		/usr/libexec/PlistBuddy -c "Set :StoredDate $(CURR_DATE_SEC)" "$application.plist"
		/usr/libexec/PlistBuddy -c "Set :Timer $hour_timer_s" "$application.plist"
		echo "$(timestamp)Notifying user again in $hour_timer hour(s)."
	elif [ "$1" == "tonight" ]; then
		/usr/libexec/PlistBuddy -c "Set :TimerType 2" $application.plist
		/usr/libexec/PlistBuddy -c "Set :StoredDate $(CURR_DATE_HOUR)" "$application.plist"
		echo "$(timestamp)Notifying user again at $tonight_time:00 hours."
	elif [ "$1" == "tomorrow" ]; then
		/usr/libexec/PlistBuddy -c "Set :TimerType 3" $application.plist
		/usr/libexec/PlistBuddy -c "Set :StoredDate $(CURR_DATE_HOUR)" "$application.plist"
		echo "$(timestamp)Notifying user again at $tonight_time:00 hours."
	fi
	exit 1
}

# Check if machine is on AC Power (if desired) and/or Quit pending application and begin installation (exit 0).
function install_app {
	power_source=$(pmset -g ps | awk '{gsub("\x27","");print $4;exit}')

	if [ "$1" == "continue" ]; then
		power_check="0"
		echo "$(timestamp)$logged_in_user selected Install, quitting and updating $application."
		killall "$application"
		exit 0
	elif [ "$power_check" == "1" ] && [ "$power_source" != "AC" ]; then
		power_notification
	else
		echo "$(timestamp)$logged_in_user selected Install, quitting and updating $application."
		killall "$application"
		exit 0
	fi
}

# Show Kiosk if notification is clicked.
function show_kiosk {
	su - "$logged_in_user" -c "/usr/local/bin/fwcontrol fwgui showKiosk"
	echo "$(timestamp)'$logged_in_user' showing Kiosk"
	echo "$(timestamp)Triggering notification again"
	exit 1
}

# Force install notification (if desired)
function force_notification {
	NOTIFICATION=$(su - "$logged_in_user" -c "/usr/local/bin/fw-notify/alerter -title '$start_title' -message '$force_message' -closeLabel 'Install' -timeout $notification_timeout -appIcon '$alert_icon'")
	case $NOTIFICATION in
	"@TIMEOUT") install_app continue ;;
    	"@CLOSED") install_app continue ;;
    	"@ACTIONCLICKED") install_app continue ;;
    	"@CONTENTCLICKED") install_app continue ;;
    	"Install") install_app continue ;;
    	**) echo "? --> $NOTIFICATION" ;;
	esac
}

# AC Power notification (if desired)
function power_notification {
	if [ "$(CURR_DATE_HOUR)" -lt "$tonight_time" ]; then
		tod="Tonight"
	elif [ "$(CURR_DATE_HOUR)" -ge "$tonight_time" ]; then
		tod="Tomorrow"
	fi

	NOTIFICATION=$(su - "$logged_in_user" -c "/usr/local/bin/fw-notify/alerter -title 'Connect to charger' -message 'Please connect to charger to continue installation.' -closeLabel 'Continue on Battery' -dropdownLabel Later -actions 'Try in $hour_timer hour(s)','Try $tod' -timeout $notification_timeout -appIcon '$alert_icon'")
	case $NOTIFICATION in
	"@TIMEOUT") timeout ;;
    	"@CLOSED") timer hour ;;
    	"@ACTIONCLICKED") timer hour ;;
    	"@CONTENTCLICKED") show_kiosk ;;
    	"Try Tomorrow") timer tomorrow ;;
    	"Try Tonight") timer tonight ;;
    	"Try in $hour_timer hour(s)") timer hour ;;
    	"Continue on Battery") install_app continue ;;
    	**) echo "? --> $NOTIFICATION" ;;
	esac
}

# Show Main Notification with options.
function main_notification {
	if [ "$(CURR_DATE_HOUR)" -lt "$tonight_time" ]; then
		tod="Tonight"
	elif [ "$(CURR_DATE_HOUR)" -ge "$tonight_time" ]; then
		tod="Tomorrow"
	fi
	
	NOTIFICATION=$(su - "$logged_in_user" -c "/usr/local/bin/fw-notify/alerter -title '$start_title' -message '$start_message' -closeLabel Install -dropdownLabel Later -actions 'Try in $hour_timer hour(s)','Try $tod' -timeout $notification_timeout -appIcon '$alert_icon'")
	case $NOTIFICATION in
	"@TIMEOUT") timeout ;;
    	"@CLOSED") timer hour ;;
    	"@ACTIONCLICKED") timer hour ;;
    	"@CONTENTCLICKED") show_kiosk ;;
    	"Try Tomorrow") timer tomorrow ;;
    	"Try Tonight") timer tonight ;;
    	"Try in $hour_timer hour(s)") timer hour ;;
    	"Install") install_app ;;
    	**) echo "? --> $NOTIFICATION" ;;
	esac
}

# Completion (post-flight) notification
function show_complete_notification {
	NOTIFICATION=$(su - "$logged_in_user" -c "/usr/local/bin/fw-notify/alerter -title '$complete_title' -message '$complete_message' -closeLabel Close -actions Open -timeout $notification_timeout -appIcon '$alert_icon'")
	case $NOTIFICATION in
	"@TIMEOUT") echo "$(timestamp)'$logged_in_user' did not acknowledge notification within $notification_timout seconds." ;;
    	"@CLOSED") echo "$(timestamp)'$logged_in_user' clicked on the default alert close button" ;;
    	"@ACTIONCLICKED") echo "$(timestamp)'$logged_in_user' clicked the alert default action button" ;;
    	"@CONTENTCLICKED") open_app ;;
	"Open") open_app ;;
    	"Close") echo "$(timestamp)'$logged_in_user' clicked on the default alert close button" ;;
    	**) echo "? --> $NOTIFICATION" ;;
	esac
}

# Generate plist for storing timer settings.
function plist_gen {
	echo "$(timestamp)Generating $application.plist in $PWD"
	/usr/libexec/PlistBuddy -c "Add :Application string $application" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :AlertIcon string $alert_icon" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :StartDate integer $(CURR_DATE_SEC)" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :StoredDate integer 0" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :TimerType integer 0" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :Timer integer 0" "$application.plist"
	/usr/libexec/PlistBuddy -c "Add :Timeout integer $notification_timeout" "$application.plist"
}

# Check timer type and whether or not to display notification.
function check_timer {
	timer_type=$(/usr/libexec/PlistBuddy -c "print :TimerType" "$application.plist")
	timer=$(/usr/libexec/PlistBuddy -c "print :Timer" "$application.plist")
	start_date=$(/usr/libexec/PlistBuddy -c "print :StartDate" "$application.plist")
	stored_date=$(/usr/libexec/PlistBuddy -c "print :StoredDate" "$application.plist")
	remainder=$(($(CURR_DATE_SEC)-stored_date))
	if [ "$timer_type" == "1" ] && [ "$remainder" -lt "$timer" ]; then
		echo "$(timestamp)Triggering notification in $((timer-remainder)) seconds."
		exit 1
	elif [ "$timer_type" == "2" ] && [ "$(CURR_DATE_HOUR)" -lt "$tonight_time" ]; then
		echo "$(timestamp)Notifying $logged_in_user again at $tonight_time:00 hours."
		exit 1
	elif [ "$timer_type" == "3" ] && [ "$(CURR_DATE_HOUR)" -gt "$tomorrow_time" ]; then
		echo "$(timestamp)Notifying $logged_in_user again at $tomorrow_time:00 hours."
		exit 1
	elif [ "$force_install" == "1" ] && [ "$(CURR_DATE_SEC)" -ge "$((start_date+force_timer_s))" ]; then
		echo "$(timestamp)Forcing $application update within $notification_timeout seconds."
		force_notification
	else
		main_notification
	fi	
}

function start {
	start_reqs
	if [ ! -f "$application.plist" ]; then
		plist_gen
		check_timer
	else
		check_timer
	fi
}

function complete {
	complete_reqs
	show_complete_notification
	reset_timer
}

# Set up Launch Arguments
for arg in "$@"
do
	if [ "$arg" == "power_check" ] || [ "$arg" == "-pc" ]; then
		power_check="1"
	elif [ "$arg" == "force" ] || [ "$arg" == "-f" ]; then
		echo "$(timestamp)Forcing $application update within $force_timer days."
		force_install="1"
	elif [ "$arg" == "start" ] || [ "$arg" == "-s" ]; then
		start
	elif [ "$arg" == "complete" ] || [ "$arg" == "-c" ]; then
		complete
	fi
done