#!/bin/bash

#  video-partial-download
#
#  Download only some parts of a video URL.
#  We must specify start time and stop time of each part.
#  $Revision: 1.1 $
#
#  Copyright (C) 2023-2023 Jordi Pujol <jordipujolp AT gmail DOT com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3, or (at your option)
#  any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#************************************************************************

SecondsToHms() {
	local time=${1}
	printf "%d\t" $((time/3600)) $(((time%3600)/60)) $((time%60))
}

TimestampToSeconds() {
	local timestamp="${@}" \
		time=0 factor=1 word
	while read -r word; do
		case "${word,,}" in
		"") : ;;
		:) let "factor*=(factor < 3600 ? 60 : 24),1" ;;
		s*) factor=1 ;;
		m*) factor=60 ;;
		h*) factor=3600 ;;
		d*) factor=86400 ;;
		0) : ;;
		[[:digit:]]*) let "time+=factor*word,1" ;;
		*) return 1 ;;
		esac
	done < <(sed -r \
	-e '/[[:blank:]]+/s///g' \
	-e ':a' \
	-e '/^0*([[:digit:]]+).*/{h;s//\1/;p
		x;s/^[[:digit:]]+//
		t a}' \
	-e '/^([^[:digit:]]+).*/{h;s//\1/;p
		x;s/^[^[:digit:]]+//
		t a}' <<< "${timestamp}" | \
	tac)

	printf '%d\n' ${time}
}

Timestamp() {
	local time="${@}"
	printf "%02d:%02d:%02d\n" \
		$(SecondsToHms $(TimestampToSeconds "${time}" || echo 0))
}

SecondsToTimestamp() {
	local time="${1}" \
		factor=86400 t unit="d" \
		timestamp=""
	while [ ${time} -gt 0 ]; do
		[ $((t=time/factor)) -eq 0 ] || {
			let "time-=t*factor,1"
			timestamp="${timestamp}${t}${unit}"
		}
		case "${unit}" in
		d) unit="h";;
		h) unit="m";;
		m) unit="s";;
		esac
		let "factor/=(factor <= 3600 ? 60 : 24),1"
	done
	printf "%s\n" "${timestamp:-0}"
}

_fileSize() {
	local f="${1}"
	stat --format '%s' "${f}"
}

_line() {
	local line=${1}
	shift
	awk -v line="${line}" \
		'NR == line {print; exit}' \
		<<< "${@}"
}

_thsSep() {
	printf "%'d\n" "${@}"
}

_natural() {
	local v
	let "line++,1"
	v="$(_line $((line+2)) "${Res}" | \
		sed -re '/^[[:blank:]]*$/s//0/')"
	[ -n "${v:=0}" ] && \
	s="$(printf '%d\n' "${v}" 2> /dev/null)" || {
		s="${v}"
		return 1
	}
}

VlcGet() {
	local url="${1}" \
		title="${2}" \
		sTime="${3}" \
		eTime="${4}" \
		lengthAprox="${5}" \
		length

	echo "vlc download \"${url}\" from $(_thsSep ${sTime}) to $(_thsSep ${eTime})," \
		"$(_thsSep ${lengthAprox}) bytes"

	vlc ${VlcOptions} \
		--no-one-instance \
		"${url}" \
		--sout "#std{access=file,dst='${title}'}" \
		--start-time ${sTime} \
		--stop-time ${eTime} \
		--run-time $((4+eTime-sTime)) \
		vlc://quit \
		> "${TmpDir}$(basename "${title}").txt" 2>&1

	if grep -qsEe "\[[[:xdigit:]]+\] access stream error:.*failure" \
	"${TmpDir}$(basename "${title}").txt"|| \
	[ ! -s "${title}" ]; then
		echo "Err: download file \"${title}\" does not exist"
		return 1
	fi
	length=$(_fileSize "${title}")
	echo "length of \"${title}\": $(_thsSep ${length}) bytes"
	[ ${length} -ge $((lengthAprox*90/100)) ] || \
		echo "Warn: download file \"${title}\" is too short"
}

GetDuration() {
	local url="${1}"
	LANGUAGE=C \
	ffprobe -hide_banner -i "${url}" 2>&1 | \
		sed -nre '/^[[:blank:]]*Duration: ([[:digit:]]+:[[:digit:]]+:[[:digit:]]+).*/{
		s//\1/;p;q}
		${q1}'
}

GetLength() {
	local url="${1}"
	if [ -s "${url}" ]; then
		length=$(_fileSize "${url}")
		echo "Length of \"${url}\"=${length}, local file"
	elif length=$(LANGUAGE=C \
	wget --verbose -T 7 --no-check-certificate --spider "${url}" 2>&1 | \
	sed -nre '/^Length: ([[:digit:]]+).*/{s//\1/;p;q};${q1}'); then
		echo "Length of \"${url}\"=${length}, usign wget"
	elif length=$( options="$(! set | \
		grep -qsEe 'PROXY=.*(localhost|127\.0\.0\.1)' || {
			printf "%s " "--noproxy"
			sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/' <<< "${url}"
		})"
	LANGUAGE=C \
	curl -sGI ${options} "${url}" 2>&1 | \
	sed -nre '/^[Cc]ontent-[Ll]ength: ([[:digit:]]+).*/{s//\1/;p;q0};${q1}'); then
		echo "Length of \"${url}\"=${length}, usign curl"
	else
		echo "Can't deduce length of \"${url}\""
		return 1
	fi
}

GetLengthM3u8() {
	local url="${1}" \
		partn lT dT
	LANGUAGE=C \
	wget --verbose -T 7 --no-check-certificate \
	-O "${TmpDir}$(basename "${url}")" \
	"${url}" \
	2> "${TmpDir}$(basename "${url}").txt" || {
		echo "Err: error retrieving \"${url}\""
		return 1
	}
	sed -ne '1{/^#EXTM3U$/!q1;q}' "${TmpDir}$(basename "${url}")" || {
		echo "Err: not a m3u file \"${TmpDir}$(basename "${url}")\""
		return 1
	}
	echo "Computing length of \"${url}\""
	dT=0
	lT=0
	while read -r partn; do
		Ext="${Ext:-"${partn##*.}"}"
		let "dT+=$(TimestampToSeconds "$(GetDuration "${partn}" || :)"),1"
		let "lT+=$(length=""
			GetLength "${partn}" 1>&2
			echo ${length:-0}),1"
	done 2>&1 < <(LANGUAGE=C \
	ffprobe -hide_banner -i "${url}" 2>&1 | \
	sed -nre "/.*Opening '(.+)' for reading.*/{s//\1/;p}")

	[ ${dT} -gt 0 ] || {
		echo "length of \"${url}\" not found"
		return 1
	}
	length=$(($(TimestampToSeconds ${duration})*lT/dT))
}

VerifyData() {
	local arg r s urlPrev line ierr \
		i j v \
		recTime recLength duration durationSeconds length

	echo "Messages"
	if [ ${#} -gt 0 ]; then
		for i in $(seq 3 $((${#} <= 6 ? ${#} : 6)) ); do
			arg="$(eval echo "\$${i}")"
			for j in 1 2; do
				s="$(printf '%s\n' "${arg}" | cut -f ${j} -s -d '-')"
				if v="$(TimestampToSeconds "${s}")"; then
					v="$(SecondsToHms ${v})"
				else
					echo "interval $((i-2))=\"${arg}\" is invalid \"${s}\""
					v="$(sed -nre '/[[:blank:]]+/s///g' \
						-e '/^0*([^:]+):0*([^:]+):0*([^:]+)$/{s//\1h\2m\3s/;p;q}' \
						-e '/.*/{s//0/;p}' <<< "${s}")"
					v="$(SecondsToHms "$(TimestampToSeconds "${v}" || echo 0)")"
				fi
				for v in ${v}; do
					[ -z "${Res}" ] && \
						Res="${1}${LF}${2}${LF}${v}" || \
						Res="${Res}${LF}${v}"
				done
			done
		done
		[ -n "${Res}" ] || \
			Res="${1:-}${LF}${2:-}${LF}0"
		Res="${Res}$(printf '\n0%.0s' \
			$(seq 1 $((2+4*6-$(wc -l <<< "${Res}")))))"
	fi

	Err=""
	Url="$(_line 1 "${Res}")"
	[ -n "${Url}" ] || {
		echo "URL must be specified"
		Err="y"
		return 0
	}
	Title="$(_line 2 "${Res}")"
	urlPrev="$(_line 1 "${ResOld}")"
	Res="$(sed -re '3,$ {/^[[:blank:]]*$/s//0/}' <<< "${Res}")"
	[ "${Url}" != "${urlPrev}" -o -z "${Title}" ] || \
	[ "$(tail -n +3 <<< "${Res}")" != "$(tail -n +3 <<< "${ResOld}")" ] || \
	[ -z "${Intervals}" ] || {
		cat "${Msgs}.bak"
		return 0
	}
	ResOld="${Res}"
	{ echo '#!/bin/sh'
		printf '"%s" \\\n' "${0}" "${Url}" "${Title}"
		r="$(tail -n +3 <<< "${Res}")"
		while [ $(wc -l <<< "${r}") -ge 6 ]; do
			s="$(head -n 6 <<< "${r}")"
			r="$(tail -n +7 <<< "${r}")"
			grep -qsxvF '0' <<< "${s}" || \
				continue
			printf " '"
			sep=""
			while read -r v; do
				printf '%s%s' "${sep}" "${v}"
				sep=":"
			done < <(head -n 3 <<< "${s}")
			printf "-"
			sep=""
			while read -r v; do
				printf '%s%s' "${sep}" "${v}"
				sep=":"
			done < <(tail -n +4 <<< "${s}")
			printf "'"
		done
		echo
	} > "${TmpDir}cmd.sh"
	tail -n +2 "${TmpDir}cmd.sh"

	VideoUrl=""
	if [ "${Url}" != "${urlPrev}" ]; then
		if duration="$(GetDuration "${Url}")"; then
			VideoUrl="${Url}"
		elif VideoUrl="$(yt-dlp "${Url}" --get-url 2> "${TmpDir}yt-dlp.txt")"; then
			duration="$(GetDuration "${VideoUrl}")" || :
		else
			grep -qsF "connection failed:" "${TmpDir}yt-dlp.txt" && \
				echo "Err: connection failed to \"${Url}\"" || \
				echo "Err: URL not found or does not contain a video"
			duration="0:0:0"
			durationSeconds=0
			Err="y"
			Ext=""
		fi
	else
		VideoUrl="${VideoUrlPrev}"
		duration="${DurationPrev}"
	fi

	length=0
	if [ -n "${VideoUrl}" -a -n "${duration}" ]; then
		if [ "${VideoUrl}" = "${VideoUrlPrev}" ]; then
			length=${LengthPrev}
			duration="${DurationPrev}"
			Ext="${ExtPrev}"
		fi
		durationSeconds="$(TimestampToSeconds "${duration}")"
		echo "video duration: ${duration}," \
			"$(_thsSep ${durationSeconds}) seconds"
		[ "${VideoUrl}" = "${Url}" ] || \
			printf '%s\n' "Real video URL:" \
				"\"${VideoUrl}\""
		if [ "${VideoUrl}" != "${VideoUrlPrev}" ]; then
			Ext=""
			if [[ ${VideoUrl} =~ .m3u8 ]] && \
			GetLengthM3u8 "${VideoUrl}" || \
			GetLength "${VideoUrl}"; then
				VideoUrlPrev="${VideoUrl}"
				LengthPrev=${length}
				DurationPrev="${duration}"
				Ext="${Ext:-"${VideoUrl##*.}"}"
				ExtPrev="${Ext}"
			else
				echo "Err: Can't find the video length"
				Err="y"
			fi
		fi
	fi

	[ ${durationSeconds:=0} -ne 0 ] || {
		echo "Err: duration is zero, therefore intervals can't be checked"
		Err="y"
	}

	[ ${length:=0} -eq 0 ] && {
		echo "Err: video length is not valid"
		Err="y"
	} || \
		echo "video length: $(_thsSep ${length}) bytes$(
		[ ${length} -ge $((durationSeconds*1024)) ] || \
			echo ", Warn: length is too short")"

	if [ -z "${Title}" ]; then
		Title="$(basename "$(yt-dlp "${Url}" --get-title | \
		sed -re "/[\"']+/s///g")")" || :
		[ -n "${Title}" -o -z "${VideoUrl}" ] || \
			Title="$(basename "$(yt-dlp "${VideoUrl}" --get-title | \
			sed -re "/[\"']+/s///g")")" || {
				Title="$(basename "${VideoUrl}")"
				Title="${Title%.*}"
			}
		[ -n "${Title}" ] || \
			Title="$(LANGUAGE=C \
			wget -T 7 --no-check-certificate -O - "${Url}" | \
			awk '/<title>.*<\/title>/{ \
			gsub(/.*<title>|<\/title>.*/,""); print; exit}')" || :
		[ -z "${Title}" ] && \
			Err="y" || \
			echo "Setting title to \"${Title}\""
	fi 2> /dev/null

	Intervals=""
	Ts=0
	Tl=0
	line=0
	for i in $(seq 1 4); do
		ierr=""
		ss=0
		se=0
		si="Interval ${i}: "
		if _natural; then
			let "ss=s*3600,S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, start hour"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		if _natural; then
			let "ss+=s*60,S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
			[ ${s} -lt 60 ] || \
				echo "Warn: interval ${i}, start minute not less than 60"
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, start minute"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		if _natural; then
			let "ss+=s,S${line}=s,1"
			[ ${s} -lt 60 ] || \
				echo "Warn: interval ${i}, start second not less than 60"
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, start second"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		si="${si}$(SecondsToTimestamp ${ss})-"
		if _natural; then
			let "se=s*3600,S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, end hour"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		if _natural; then
			let "se+=s*60,S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
			[ ${s} -lt 60 ] || \
				echo "Warn: interval ${i}, end minute not less than 60"
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, end minute"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		if _natural; then
			let "se+=s,S${line}=s,1"
			[ ${s} -lt 60 ] || \
				echo "Warn: interval ${i}, end second not less than 60"
		else
			eval S${line}='${s}'
			echo "Err: error in interval ${i}, end second"
			ierr="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		si="${si}$(SecondsToTimestamp ${se})"

		[ ${durationSeconds} -ne 0 ] || {
			Err="${Err:-${ierr}}"
			echo "${si} from $(_thsSep ${ss}) to $(_thsSep ${se})"
			continue
		}

		recTime=0
		recLength=0
		if [ ${se} -gt $((durationSeconds)) ]; then
			si="${si} out of limits"
			ierr="y"
		elif [ ${ss} -lt ${se} ]; then
			Intervals="${Intervals}${i} "
			let "Is${i}=ss,\
				Ie${i}=(se == durationSeconds ? se+1 : se),\
				recTime=Ie${i}-Is${i},1"
			[ ${durationSeconds} -eq 0 ] || \
				let "recLength=recTime*length/durationSeconds,1"
			let "Il${i}=recLength,1"
		elif [ ${ss} -ne 0 -o ${se} -ne 0 ]; then
			si="${si} invalid"
			ierr="y"
		fi
		test ${recLength} -eq 0 -a -z "${ierr}" || \
			echo "${si} from $(_thsSep ${ss}) to $(_thsSep ${se})," \
				"downloading $(_thsSep ${recTime}) seconds," \
				"$(_thsSep ${recLength}) bytes"
		let "Ts+=recTime,\
			Tl+=recLength,1"
		Err="${Err:-${ierr}}"
	done

	if [ -n "${Intervals}" ]; then
		echo "Downloading $(_thsSep ${Ts}) seconds$( \
			test ${Tl} -eq 0 || \
				echo ", $(_thsSep ${Tl}) bytes")"
	elif [ -z "${Err}" ]; then
		echo "Err: have not defined any interval"
		Err="y"
	fi
	[ -z "${Err}" ] || {
		echo "Err: Invalid data"
		ResOld="${ResOld}${LF}${Err}"
	}
}

Main() {
	readonly LF=$'\n' \
		MyId="$(date +%s)" \
		CurrDir="$(readlink -f .)/"
	readonly TmpDir="${CurrDir}tmp-${MyId}/"
	readonly Msgs="${TmpDir}msgs.txt"

	local Url="" Title="" StdOut \
		VideoUrl VideoUrlPrev DurationPrev LengthPrev ExtPrev \
		Res ResOld Err Ext \
		Sh Sm Ss \
		S1="" S2="" S3="0" \
		S4="" S5="" S6="0" \
		S7="" S8="" S9="0" \
		S10="" S11="" S12="0" \
		S13="" S14="" S15="0" \
		S16="" S17="" S18="0" \
		S19="" S20="" S21="0" \
		S22="" S23="" S24="0" \
		VlcOptions \
		Intervals \
		i title playlist length rc

	mkdir -p "${TmpDir}"
	VlcOptions=""
	if [ -z "${Debug:=}" ]; then
		VlcOptions="-I dummy"
	elif [ "${Debug}" = "xtrace" ]; then
		VlcOptions="-v"
		set +x
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${TmpDir}log.txt"
		set -x
	fi

	Res=""
	ResOld=""
	VideoUrlPrev=""
	LengthPrev=0
	DurationPrev=""
	ExtPrev=""
	exec {StdOut}>&1
	exec > >(tee "${Msgs}")
	VerifyData "${@}"
	eval exec "1>&${StdOut}" "${StdOut}>&-"
	Err="y"
	rc=1
	while [ -n "${Err}" -o ${rc} -ne 0 ]; do
		rc=0
		Res="$(export DIALOGRC=""
		dialog --stdout --no-shadow --colors \
		--begin 24 0 --title Messages \
		--tailboxbg "${Msgs}" 18 172 \
		--and-widget --begin 0 0 \
		--title "VLC download video parts" --colors \
		--ok-label "Download" \
		--extra-button --extra-label "Info" \
		--form ' Enter Values, press Enter:' 24 172 20 \
		'URL . . . . . >' 1 1 "${Url}" 1 22 50 1024 \
		'Description . ' 3 1 "${Title}" 3 22 50 1024 \
		'Interval . . ' 5 1 "${S1}" 5 22 4 4 'h' 5 26 "${S2}" 5 27 3 3 'm' 5 30 "${S3}" 5 31 9 9 's-' 5 40 "${S4}" 5 42 4 4 'h' 5 46 "${S5}" 5 47 3 3 'm' 5 50 "${S6}" 5 51 9 9 's' 5 60 '' 5 60 0 0 \
		'Interval . . ' 7 1 "${S7}" 7 22 4 4 'h' 7 26 "${S8}" 7 27 3 3 'm' 7 30 "${S9}" 7 31 9 9 's-' 7 40 "${S10}" 7 42 4 4 'h' 7 46 "${S11}" 7 47 3 3 'm' 7 50 "${S12}" 7 51 9 9 's' 7 60 '' 7 60 0 0 \
		'Interval . . ' 9 1 "${S13}" 9 22 4 4 'h' 9 26 "${S14}" 9 27 3 3 'm' 9 30 "${S15}" 9 31 9 9 's-' 9 40 "${S16}" 9 42 4 4 'h' 9 46 "${S17}" 9 47 3 3 'm' 9 50 "${S18}" 9 51 9 9 's' 9 60 '' 9 60 0 0 \
		'Interval . . ' 11 1 "${S19}" 11 22 4 4 'h' 11 26 "${S20}" 11 27 3 3 'm' 11 30 "${S21}" 11 31 9 9 's-' 11 40 "${S22}" 11 42 4 4 'h' 11 46 "${S23}" 11 47 3 3 'm' 11 50 "${S24}" 11 51 9 9 's' 11 60 '' 11 60 0 0 \
		)" || \
			rc=${?}
		[ ${rc} -ne 1 -a ${rc} -ne 255 ] || \
			exit 0

		tail -n +2 "${Msgs}" > "${Msgs}.bak"
		exec {StdOut}>&1
		rm -f "${Msgs}"
		exec > >(tee "${Msgs}")
		VerifyData
		eval exec "1>&${StdOut}" "${StdOut}>&-"
		rm -f "${Msgs}.bak"
	done

	Title="${Title}-${MyId}.${Ext}"
	exec {StdOut}>&1
	exec > >(tee -a "${Msgs}")

	if [ $(echo "${Intervals}" | wc -w) -eq 1 ]; then
		VlcGet "${VideoUrl}" "${Title}" $((Is${Intervals})) \
		$((Ie${Intervals})) $((Il${Intervals})) || \
			echo "Err: error in vlc download"
	else
		playlist="${TmpDir}playlist.txt"
		: > "${playlist}"
		Err=""
		for i in ${Intervals}; do
			title="${TmpDir}${i}.${Ext}"
			if ! VlcGet "${VideoUrl}" "${title}" $((Is${i})) \
			$((Ie${i})) $((Il${i})); then
				echo "Err: error in vlc download, interval ${i}"
				Err="y"
			fi
			echo "file '$(basename "${title}")'" >> "${playlist}"
		done
		if [ -z "${Err}" ]; then
			echo "ffmpeg concat" $(cat "${playlist}")
			if ! ( cd "${TmpDir}"
			ffmpeg -nostdin -hide_banner -y \
			-f concat -safe 0 -i "$(basename "${playlist}")" \
			-c:v copy "${CurrDir}${Title}" \
			> "${TmpDir}${Title}.txt" 2>&1
			); then
				echo "Err: error in video concatenation"
			fi
			if [ -s "${CurrDir}${Title}" ]; then
				length=$(_fileSize "${CurrDir}${Title}")
				echo "length of \"${CurrDir}${Title}\":" \
					"$(_thsSep ${length}) bytes"
			fi
		fi
	fi
	[ -s "${CurrDir}${Title}" ] || \
		echo "Err: error in download"
	eval exec "1>&${StdOut}" "${StdOut}>&-"
	clear
	cat "${Msgs}" >&2
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber

declare -ar ARGV=("${@}")
readonly ARGC=${#}

Main "${@}"
