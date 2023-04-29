#!/bin/bash

SecondsToHms() {
	local time=${1}
	printf "%d\n" $((time/3600)) $(((time%3600)/60)) $((time%60))
}

TimestampToSeconds() {
	local timestamp="${@}" \
		time=0 factor=1 word
	while read -r word; do
		case "${word,,}" in
		"") : ;;
		:) factor=$((factor < 3600 ? factor*60 : factor*24)) ;;
		s*) factor=1 ;;
		m*) factor=60 ;;
		h*) factor=3600 ;;
		d*) factor=86400 ;;
		0) : ;;
		[[:digit:]]*) time=$((time+factor*word)) ;;
		*) echo "Err: invalid word \"${word}\"" >&2; return 1 ;;
		esac
	done < <(sed -re ':a' \
	-e '/^[[:blank:]]+/{s///
		t a}' \
	-e '/^0*([[:digit:]]+).*/{h;s//\1/;p
		x;s/^[[:digit:]]+//
		t a}' \
	-e '/^([^[:digit:]]+).*/{h;s//\1/;p
		x;s/^[^[:digit:]]+//
		t a}' <<< "${timestamp}" | \
	tac)

	printf '%d\n' ${time}
}

TimeStamp() {
	local time="${@}"
	printf "%02d:%02d:%02d\n" $(SecondsToHms $(TimestampToSeconds "${time}"))
}

set -o errexit

TimestampToSeconds "0:0:0"

TimestampToSeconds ":0:0"

TimestampToSeconds "1101"

TimestampToSeconds "h" "10m" "s"

TimestampToSeconds "1 hour" "10 minutes"

TimestampToSeconds "1h10m"

TimestampToSeconds "1 day" "3 hours"

TimestampToSeconds "10 seconds" "3 hours"

TimestampToSeconds "009:11:09"

TimestampToSeconds "0000:009:59"

TimestampToSeconds "0:009:59"

TimeStamp "1 hour" "10 minutes" "4 seconds"

TimeStamp "10m4s1h"
