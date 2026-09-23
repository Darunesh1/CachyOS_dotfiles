#!/bin/bash

# Configuration
WARNING_LEVEL=10
CRITICAL_LEVEL=5
SLEEP_TIME=60

# State variable to prevent spamming the 10% warning
TEN_PERCENT_WARNED=false

while true; do
    # Read current capacity and status
    BATTERY_CAPACITY=$(cat /sys/class/power_supply/BAT0/capacity)
    BATTERY_STATUS=$(cat /sys/class/power_supply/BAT0/status)

    # Only send warnings if the laptop is actively discharging
    if [[ "$BATTERY_STATUS" == "Discharging" ]]; then
        
        if [[ "$BATTERY_CAPACITY" -le "$CRITICAL_LEVEL" ]]; then
            # Continuous warning every loop (60s) if <= 5%
            notify-send -u critical -a "Power Management" -i battery-caution-symbolic "Battery Critical!" "Charge dropping below ${BATTERY_CAPACITY}%. Plug in immediately!"
            
        elif [[ "$BATTERY_CAPACITY" -le "$WARNING_LEVEL" ]]; then
            # One-time warning if <= 10%
            if [ "$TEN_PERCENT_WARNED" = false ]; then
                notify-send -u normal -a "Power Management" -i battery-low-symbolic "Battery Low" "Battery is at ${BATTERY_CAPACITY}%. Please plug in soon."
                TEN_PERCENT_WARNED=true
            fi
        fi
        
    else
        # Reset the 10% warning state if the laptop is plugged in (Charging, Full, etc.)
        TEN_PERCENT_WARNED=false
    fi

    # Wait before checking again
    sleep $SLEEP_TIME
done
