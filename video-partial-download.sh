#!/bin/bash

_unquote() {
	printf "%s\n" "${@}" | \
		sed -re "s/^([\"]([^\"]*)[\"]|[']([^']*)['])$/\2\3/"
}

HmsFromSeconds() {
	local time=${1}
	printf "%d\n" $((time/3600)) $(((time%3600)/60)) $((time%60))
}

SecondsFromTimestamp() {
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
		*) return 1 ;;
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
	printf "%02d:%02d:%02d\n" $(HmsFromSeconds $(SecondsFromTimestamp "${time}"))
}

_fileSize() {
	local f="${1}"
	stat --format %s "${f}"
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
	local v w
	v="$(_line ${line} "${Res}" | \
		sed -re '/^[[:blank:]]+$/s///')"
	if w="$(printf '%d\n' "${v}" 2> /dev/null)"; then
		printf '%d\n' "${w}"
	else
		printf '%s\n' "${v:-"0"}"
		[ -z "${v}" ] || \
			return 1
	fi
}

VlcGet() {
	local url="${1}" \
		title="${2}" \
		sTime="${3}" \
		eTime="${4}" \
		lengthAprox="${5}" \
		length

	echo "vlc download \"${url}\" from $(_thsSep ${sTime}) to $(_thsSep ${eTime})," \
		"aprox.length $(_thsSep ${lengthAprox}) bytes"

	vlc ${VlcOptions} \
		--no-one-instance \
		"${url}" \
		--sout "file/${Mux}:${title}" \
		--start-time ${sTime} \
		--stop-time ${eTime} \
		--run-time $((4+eTime-sTime)) \
		vlc://quit \
		> "${TmpDir}$(basename "${title}").txt" 2>&1

	if [ ! -s "${title}" ]; then
		echo "Err: download file \"${title}\" does not exist"
		return 1
	fi
	length=$(_fileSize "${title}")
	echo "length of \"${title}\" is $(_thsSep ${length}) bytes"
	[ ${length} -ge $((lengthAprox*90/100)) ] || \
		echo "Warn: download file \"${title}\" is too short"
}

GetDuration() {
	local r
	r="$(LANGUAGE=C \
	ffmpeg -nostdin -hide_banner -y -i "${VideoUrl:-"${Url}"}" 2>&1 | \
	sed -n '/^Input #0/,/^At least one/ {/^[^A]/p}')"
	printf '%s\n' "${r}" | \
	sed -nre '/^[[:blank:]]*Duration: ([[:digit:]]+:[[:digit:]]+:[[:digit:]]+).*/{s//\1/;p;q};${q1}' && \
		return 0 || \
		echo "100:0:0"
	[ -n "${VideoUrl}" ] || \
	printf '%s\n' "${r}" | grep -qsie 'Stream.*Video:' || \
		return 1
}

VerifyData() {
	local fdout arg p r s line ext \
		i j v \
		duration durationSeconds

	exec 6>&1
	rm -f "${Msgs}"
	exec > "${Msgs}"
	echo "Messages"
	if [ ${#} -gt 0 ]; then
		for i in $(seq 3 $((${#} <= 6 ? ${#} : 6)) ); do
			arg="$(eval echo "\$${i}")"
			for j in 1 2; do
				s="$(printf '%s\n' "${arg}" | cut -f ${j} -s -d '-')"
				v="$(SecondsFromTimestamp "${s}")" || \
					echo "interval $((i-3))=\"${arg}\" is invalid \"${s}\""
				for v in $(HmsFromSeconds ${v:-0}); do
					[ -z "${Res}" ] && \
						Res="${1}${LF}${2}${LF}${v}" || \
						Res="${Res}${LF}${v}"
				done
			done
		done
		[ ${#} -eq 0 ] || \
		[ -n "${Res}" ] || \
			Res="${1:-}${LF}${2:-}"
		for i in $(seq $((${#}+1)) 6); do
			Res="${Res}${LF}0"
		done

		ResOld=""
	fi

	Err=""
	Url="$(_line 1 "${Res}")"
	[ -n "${Url}" ] || {
		echo "URL must be specified"
		Err="y"
		return 0
	}
	Title="$(_line 2 "${Res}")"
	Res="$(sed -re '3,$ {/^[[:blank:]]*$/s//0/}' <<< "${Res}")"
	[ "${Url}" != "$(_line 1 "${ResOld}")" -o -z "${Title}" ] || \
	[ "$(tail -n +3 <<< "${Res}")" != "$(tail -n +3 <<< "${ResOld}")" ] || \
		return 0
	ResOld="${Res}"
	Res="$(tail -n +3 <<< "${Res}")"
	{ echo '#!/bin/sh'
		printf '%s %s %s \\\n' "${0}" "'${Url}'" "'${Title}'"
		r="${Res}"
		while p=$(wc -l <<< "${r}");
		[ ${p} -gt 0 -a $((p%6)) -eq 0 ]; do
			s="$(head -n 6 <<< "${r}")"
			! grep -qsxvF '0' <<< "${s}" || {
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
			}
			r="$(tail -n +7 <<< "${r}")"
		done
		echo
	} > "${TmpDir}cmd.sh"
	tail -n +2 "${TmpDir}cmd.sh"

	VideoUrl=""
	if duration="$(GetDuration)"; then
		VideoUrl="${Url}"
	elif VideoUrl="$(yt-dlp "${Url}" --get-url 2> /dev/null)"; then
		duration="$(GetDuration)"
	fi
	size=0
	if [ -z "${VideoUrl}" ]; then
		duration="0:0:0"
		durationSeconds=0
		echo "this URL is invalid"
		Err="y"
	else
		duration="${duration:-"100:0:0"}"
		[ "${VideoUrl}" = "${Url}" ] || \
			echo "Real video URL is \"${VideoUrl}\""
		durationSeconds="$(SecondsFromTimestamp "${duration}")"
		echo "video duration is \"${duration}\"," \
			"$(_thsSep ${durationSeconds}) seconds"
		# size
		if [ -s "${VideoUrl}" ]; then
			size="$(_fileSize "${VideoUrl}")"
		elif size="$(
		options="$(! set | \
			grep -qsEe 'PROXY=.*(localhost|127\.0\.0\.1)' || {
				printf "%s " "--noproxy"
				sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/' <<< "${VideoUrl}"
			})"
		LANGUAGE=C \
		curl -sGI ${options} "${VideoUrl}" 2>&1 | \
		sed -nre '/^[Cc]ontent-[Ll]ength: ([[:digit:]]+).*/{s//\1/;p;q0};${q1}')"; then
			:
		else
			size="$(LANGUAGE=C \
				wget --verbose --spider -T 7 \
				--no-check-certificate "${VideoUrl}" 2>&1 | \
				sed -nre '/^Length: ([[:digit:]]+).*/{s//\1/;p;q}')" || :
		fi
	fi
	[ ${size:=0} -eq 0 ] && \
		echo "video size is invalid" || \
		echo "video size is $(_thsSep ${size}) bytes"

	if [ -z "${Title}" ]; then
		if Info="$(yt-dlp "${Url}" --get-title 2> /dev/null | \
		sed -re "/[\"']+/s///g")"; then
			Title="${Info}"
			echo "Setting title from Web page to \"${Title}\""
		elif [ -n "${VideoUrl}" ] && \
		Title="$(yt-dlp "${VideoUrl}" --get-title 2> /dev/null | \
		sed -re "/[\"']+/s///g")"; then
			echo "Setting title from video URL to \"${Title}\""
		else
			Title="$(basename "${Url}")"
			Title="${Title%.*}"
			echo "Setting title from URL name to \"${Title}\""
		fi
	fi

# mpeg1 	MPEG-1 multiplexing - recommended for portability. Only works with mp1v video and mpga audio, but works on all known players
# ts 	MPEG Transport Stream, primarily used for streaming MPEG. Also used in DVDs
# ps 	MPEG Program Stream, primarily used for saving MPEG data to disk.
# mp4 	MPEG-4 Mux format, used only for MPEG-4 video and MPEG audio.
# avi 	AVI
# asf 	ASF
# dummy 	dummy output, can be used in creation of MP3 files.
# ogg 	Xiph.org's ogg container format. Can contain audio, video, and metadata

	ext="${Url##*.}"
	case "${ext}" in
		mp4) Mux="mp4" ;;
		*) Mux="ts" ;;
	esac

	Intervals=""
	Ts=0
	Tl=0
	Err=""
	line=0
	for i in $(seq 1 4); do
		ss=0
		se=0
		si="Interval ${i} "
		let line++,1
		if s="$(_natural)"; then
			ss=${s}
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, start hour"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}h"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			ss=$((ss*60+s))
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, start minute"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}m"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			ss=$((ss*60+s))
			let "S${line}=s,1"
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, start second"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}s"
		[ "${si}" != "Interval ${i} " ] && \
			si="${si}-" || \
			si="${si}0-"
		let line++,1
		if s="$(_natural)"; then
			se=${s}
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end hour"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}h"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			se=$((se*60+s))
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end minute"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}m"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			se=$((se*60+s))
			let "S${line}=s,1"
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end second"
			Err="y"
		fi
		s="$(eval echo "\${S${line}:-0}")"
		[ "${s}" = "0" ] || \
			si="${si}${s}s"
		[ ${si: -1} != "-" ] || \
			si="${si}0"
		seconds=0
		length=0
		[ ${se} -ne ${durationSeconds} ] || \
			let "se++,1"
		if [ ${ss} -lt ${se} ]; then
			Intervals="${Intervals}${i} "
			let "Is${i}=ss,1"
			let "Ie${i}=se,1"
			seconds=$((se-ss))
			[ ${durationSeconds} -eq 0 ] || \
				length=$((seconds*size/durationSeconds))
			let "Il${i}=length,1"
		elif [ ${ss} -ne 0 -o ${se} -ne 0 ]; then
			si="${si} invalid"
			Err="y"
		fi
		if [ ${se} -gt $((durationSeconds+1)) ]; then
			si="${si} out of limits"
			Err="y"
		fi
		echo "${si} from ${ss} to ${se}," \
			"$(test ${length} -eq 0 || \
				echo "$(_thsSep ${seconds}) seconds,")" \
			"$(test ${length} -eq 0 || \
				echo "aprox. $(_thsSep ${length}) bytes")"
		Ts=$((Ts+seconds))
		Tl=$((Tl+length))
	done

	if [ -n "${Intervals}" ]; then
		echo "Downloading $(_thsSep ${Ts}) seconds," \
			"$(test ${Tl} -eq 0 || \
				echo "aprox. $(_thsSep ${Tl}) bytes")"
	else
		echo "have not defined any interval"
		Err="y"
	fi
	[ -z "${Err}" ] || {
		echo "Err: Invalid data"
		ResOld="${Res}${LF}${Err}"
	}
	exec 1>&6 6>&-
}

Main() {
	readonly LF=$'\n' \
		MyId="$(date +%s)" \
		CurrDir="$(readlink -f .)/"
	readonly TmpDir="${CurrDir}tmp-${MyId}/"
	readonly Msgs="${TmpDir}msgs.txt"

	local Url="" Title="" VideoUrl \
		Res ResOld Err Mux \
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
		i title files rc

	mkdir "${TmpDir}"
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
	VerifyData "${@}"
	Err="y"
	rc=1
	while [ -n "${Err}" -o ${rc} -ne 0 ]; do
		rc=0
		Res="$(export DIALOGRC=""
		dialog --stdout --no-shadow --colors \
		--begin 29 0 --title Messages \
		--tailboxbg "${Msgs}" 14 172 \
		--and-widget --begin 0 0 \
		--title "VLC download video parts" --colors \
		--extra-button --extra-label "Info" \
		--form ' Enter Values, press Enter:' 28 172 20 \
		'' 1 1 'URL . . . . . >' 1 1 0 0 '' 1 22 "${Url}" 1 22 50 1024 \
		'' 3 1 'Description . ' 3 1 0 0 '' 3 22 "${Title}" 3 22 50 1024 \
		'' 5 1 'Interval . . ' 5 1 0 0 '' 5 22 "${S1}" 5 22 4 4 '' 5 26 'h' 5 26 0 0 '' 5 27 "${S2}" 5 27 3 3 '' 5 30 'm' 5 30 0 0 '' 5 31 "${S3}" 5 31 3 3 '' 5 34 's-' 5 34 0 0 '' 5 36 "${S4}" 5 36 4 4 '' 5 40 'h' 5 40 0 0 '' 5 41 "${S5}" 5 41 3 3 '' 5 44 'm' 5 44 0 0 '' 5 45 "${S6}" 5 45 3 3 '' 5 48 's' 5 48 0 0 \
		'' 7 1 'Interval . . ' 7 1 0 0 '' 7 22 "${S7}" 7 22 4 4 '' 7 26 'h' 7 26 0 0 '' 7 27 "${S8}" 7 27 3 3 '' 7 30 'm' 7 30 0 0 '' 7 31 "${S9}" 7 31 3 3 '' 7 34 's-' 7 34 0 0 '' 7 36 "${S10}" 7 36 4 4 '' 7 40 'h' 7 40 0 0 '' 7 41 "${S11}" 7 41 3 3 '' 7 44 'm' 7 44 0 0 '' 7 45 "${S12}" 7 45 3 3 '' 7 48 's' 7 48 0 0 \
		'' 9 1 'Interval . . ' 9 1 0 0 '' 9 22 "${S13}" 9 22 4 4 '' 9 26 'h' 9 26 0 0 '' 9 27 "${S14}" 9 27 3 3 '' 9 30 'm' 9 30 0 0 '' 9 31 "${S15}" 9 31 3 3 '' 9 34 's-' 9 34 0 0 '' 9 36 "${S16}" 9 36 4 4 '' 9 40 'h' 9 40 0 0 '' 9 41 "${S17}" 9 41 3 3 '' 9 44 'm' 9 44 0 0 '' 9 45 "${S18}" 9 45 3 3 '' 9 48 's' 9 48 0 0 \
		'' 11 1 'Interval . . ' 11 1 0 0 '' 11 22 "${S19}" 11 22 4 4 '' 11 26 'h' 11 26 0 0 '' 11 27 "${S20}" 11 27 3 3 '' 11 30 'm' 11 30 0 0 '' 11 31 "${S21}" 11 31 3 3 '' 11 34 's-' 11 34 0 0 '' 11 36 "${S22}" 11 36 4 4 '' 11 40 'h' 11 40 0 0 '' 11 41 "${S23}" 11 41 3 3 '' 11 44 'm' 11 44 0 0 '' 11 45 "${S24}" 11 45 3 3 '' 11 48 's' 11 48 0 0 \
		)" || \
			rc=${?}
		[ ${rc} -ne 1 -a ${rc} -ne 255 ] || \
			exit 0

		VerifyData
	done

	Title="${Title}-${MyId}.mpg"
	exec 6>&1
	exec > >(tee -a "${Msgs}")

	if [ $(echo "${Intervals}" | wc -w) -eq 1 ]; then
		VlcGet "${VideoUrl}" "${Title}" $((Is${Intervals})) \
		$((Ie${Intervals})) $((Il${Intervals})) || \
			echo "error in vlc download"
	else
		files="${TmpDir}files.txt"
		: > "${files}"
		Err=""
		for i in ${Intervals}; do
			title="${TmpDir}${i}.mpg"
			if ! VlcGet "${VideoUrl}" "${title}" $((Is${i})) \
			$((Ie${i})) $((Il${i})); then
				echo "error in vlc download"
				Err="y"
			fi
			echo "file '$(basename "${title}")'" >> "${files}"
		done
		if [ -z "${Err}" ]; then
			echo "ffmpeg concat" $(cat "${files}")
			if ! ( cd "${TmpDir}"
			ffmpeg -nostdin -hide_banner -y \
			-f concat -safe 0 -i "$(basename "${files}")" \
			-c:v copy "${CurrDir}${Title}" \
			> "${TmpDir}${Title}.txt" 2>&1
			); then
				echo "error in video concatenation"
			fi
			if [ -s "${CurrDir}${Title}" ]; then
				length=$(_fileSize "${CurrDir}${Title}")
				echo "length of \"${CurrDir}${Title}\" is" \
					"$(_thsSep ${length}) bytes"
			fi
		fi
	fi
	[ -s "${CurrDir}${Title}" ] || \
		echo "error in download"
	exec 1>&6 6>&-
	clear
	cat "${Msgs}" >&2
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber

declare -ar ARGV=("${@}")
readonly ARGC=${#}

Main "${@}"
