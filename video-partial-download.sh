#!/bin/bash

_unquote() {
	sed -re "s/^([\"]([^\"]*)[\"]|[']([^']*)['])$/\2\3/" \
		<<< "${@}"
}

_timeSeconds() {
	local time="${1}"
	time="$(sed -nre '/^[0]+([[:digit:]]+)/s//\1/' \
		-e '/([^[:digit:]])0([[:digit:]])/s//\1\2/g' \
		-e 's/^([[:digit:]]+):([[:digit:]]+):([[:digit:]]+)$/((\1*60)+\2)*60+\3/p' \
		<<< "${time}")"
	echo $((${time:-0}))
}

_fileSize() {
	local f="${1}"
	stat --format %s "${f}"
}

_line() {
	local line=${1}
	shift
	awk -v line="${line}" \
		'NR == line {print; rc=1; exit}
		END{if (! rc) print 0; exit}' \
		<<< "${@}"
}

_thsSep() {
	printf "%'d\n" "${@}"
}

_natural() {
	local v
	v="$(_line ${line} "${RES}")"
	if ! printf '%s\n' "${v}" | grep -qsxEe "[[:digit:]]+"; then
		printf '%s\n' "${v}"
		return 1
	fi
	printf '%d\n' "${v}"
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

	vlc ${vlcOptions} \
		--no-one-instance \
		"${url}" \
		--sout "file/${mux}:${title}" \
		--start-time ${sTime} \
		--stop-time ${eTime} \
		--run-time $((4+eTime-sTime)) \
		vlc://quit \
		> "${tmpDir}$(basename "${title}").txt" 2>&1

	if [ ! -s "${title}" ]; then
		echo "Err: download file \"${title}\" does not exist"
		return 1
	fi
	length=$(_fileSize "${title}")
	echo "length of \"${title}\" is $(_thsSep ${length}) bytes"
	[ ${length} -ge $((lengthAprox*90/100)) ] || \
		echo "Warn: download file \"${title}\" is too short"
}

VerifyData() {
	local p r s \
		duration durationSeconds getVideoUrl
	: > "${msgs}"
	echo "Messages"
	err=""
	Url="$(_line 1 "${RES}")"
	[ -n "${Url}" ] || {
		echo "URL must be specified"
		return 0
	}
	Title="$(_line 2 "${RES}")"
	RES="$(printf '%s\n' "${RES}" | \
		sed -re '/^[[:blank:]]*$/s//0/' | \
		tail -n +3)"
	{ echo '#!/bin/sh'
		printf '%s %s %s ' "${0}" "'${Url}'" "'${Title}'"
		r="${RES}"
		while p=$(wc -l <<< "${r}");
		[ ${p} -gt 0 -a $((p%6)) -eq 0 ]; do
			s="$(printf '%s\n' ${r} | head -n 6)"
			! grep -qsxvF '0' <<< "${s}" || \
				printf "'%s:%s:%s-%s:%s:%s' " ${s}
			r="$(printf '%s\n' ${r} | tail -n +7)"
		done
		echo
	} > "${tmpDir}cmd.sh"
	echo 'Command'
	printf '%s %s %s ' "${0}" "'${Url}'" "'${Title}'"
	r="${RES}"
	while p=$(wc -l <<< "${r}");
	[ ${p} -gt 0 -a $((p%6)) -eq 0 ]; do
		s="$(printf '%s\n' ${r} | head -n 6)"
		! grep -qsxvF '0' <<< "${s}" || \
			printf "'%s:%s:%s-%s:%s:%s' " ${s}
		r="$(printf '%s\n' ${r} | tail -n +7)"
	done
	echo

	VideoUrl=""
	duration=""
	getVideoUrl=""
	while [ -z "${duration}" -o -z "${getVideoUrl}" ]; do
		if duration="$(LANGUAGE=C \
		ffmpeg -nostdin -hide_banner -y -i "${VideoUrl:-"${Url}"}" 2>&1 | \
		sed -n '/^Input #0/,/^At least one/ {/^[^A]/p}' | \
		sed -nre '/^[[:blank:]]*Duration: ([[:digit:]]+:[[:digit:]]+:[[:digit:]]+).*/{s//\1/;p;q}')" && \
		[ -n "${duration}" ]; then
			VideoUrl="${VideoUrl:-"${Url}"}"
			getVideoUrl="y"
		elif [ -z "${getVideoUrl}" ]; then
			VideoUrl="$(yt-dlp "${Url}" --get-url 2> /dev/null)" || :
			getVideoUrl="y"
			continue
		fi
	done
	if [ -z "${VideoUrl}" ]; then
		duration="0:0:0"
		echo "this URL is invalid"
		err="y"
	elif [ "${VideoUrl}" != "${Url}" ]; then
		echo "Real video URL is \"${VideoUrl}\""
	fi
	durationSeconds="$(_timeSeconds "${duration}")"
	echo "video duration is \"${duration}\"," \
		"$(_thsSep ${durationSeconds}) seconds"
	size=""
	if [ -n "${VideoUrl}" ]; then
		if [ -s "${VideoUrl}" ]; then
			size="$(_fileSize "${VideoUrl}")"
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
		if Info="$(yt-dlp "${Url}" --get-title 2> /dev/null)"; then
			Title="${Info}"
			echo "Setting title to \"${Title}\""
		elif [ -n "${VideoUrl}" ] && \
		Title="$(yt-dlp "${VideoUrl}" --get-title 2> /dev/null)"; then
			echo "Setting title to \"${Title}\""
		else
			Title="$(basename "${Url}")"
			Title="${Title%.*}"
			echo "Setting title to \"${Title}\""
		fi
	fi

# mpeg1 	MPEG-1 multiplexing - recommended for portability. Only works with mp1v video and mpga audio, but works on all known players
# ts 	MPEG Transport Stream, primarily used for streaming MPEG. Also used in DVDs
# ps 	MPEG Program Stream, primarily used for saving MPEG data to disk.
# mp4 	MPEG-4 mux format, used only for MPEG-4 video and MPEG audio.
# avi 	AVI
# asf 	ASF
# dummy 	dummy output, can be used in creation of MP3 files.
# ogg 	Xiph.org's ogg container format. Can contain audio, video, and metadata

	ext="${Url##*.}"
	case "${ext}" in
		mp4) mux="mp4" ;;
		*) mux="ts" ;;
	esac

	line=0
	intervals=""
	Ts=0
	Tl=0
	err=""
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
			err="y"
		fi
		si="${si}$((S${line}))h:"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			ss=$(((ss*60)+s))
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, start minute"
			err="y"
		fi
		si="${si}$((S${line}))m:"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			ss=$(((ss*60)+s))
			let "S${line}=s,1"
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, start second"
			err="y"
		fi
		si="${si}$((S${line}))s-"
		let line++,1
		if s="$(_natural)"; then
			se=${s}
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end hour"
			err="y"
		fi
		si="${si}$((S${line}))h:"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			se=$(((se*60)+s))
			let "S${line}=s,1"
			[ $((S${line})) -gt 0 ] || \
				eval "S${line}="
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end minute"
			err="y"
		fi
		si="${si}$((S${line}))m:"
		let line++,1
		if s="$(_natural)" && [ ${s} -lt 60 ]; then
			se=$(((se*60)+s))
			let "S${line}=s,1"
		else
			eval S${line}='${s}'
			echo "error in interval ${i}, end second"
			err="y"
		fi
		si="${si}$((S${line}))s"
		seconds=0
		length=0
		[ ${se} -ne ${durationSeconds} ] || \
			let "se++,1"
		if [ ${ss} -lt ${se} ]; then
			intervals="${intervals}${i} "
			let "Is${i}=ss,1"
			let "Ie${i}=se,1"
			seconds=$((se-ss))
			[ ${durationSeconds} -eq 0 ] || \
				length=$((seconds*size/durationSeconds))
			let "Il${i}=length,1"
		elif [ ${ss} -ne 0 -o ${se} -ne 0 ]; then
			si="${si} invalid"
			err="y"
		fi
		if [ ${se} -gt $((durationSeconds+1)) ]; then
			si="${si} out of limits"
			err="y"
		fi
		echo "${si} from ${ss} to ${se}," \
			"$(test ${length} -eq 0 || \
				echo "$(_thsSep ${seconds}) seconds,")" \
			"$(test ${length} -eq 0 || \
				echo "aprox. $(_thsSep ${length}) bytes")"
		Ts=$((Ts+seconds))
		Tl=$((Tl+length))
	done

	echo "Downloading $(_thsSep ${Ts}) seconds," \
		"$(test ${Tl} -eq 0 || \
			echo "aprox. $(_thsSep ${Tl}) bytes")"

	[ -n "${intervals}" ] || {
		echo "have not defined any interval"
		err="y"
	}
}

Main() {
	readonly LF=$'\n' \
		myId="$(date +%s)" \
		currDir="$(readlink -f .)/"
	readonly tmpDir="${currDir}tmp-${myId}/"
	readonly msgs="${tmpDir}msgs.txt"

	local Url="" Title="" VideoUrl \
		ext mux \
		Sh Sm Ss \
		S1="" S2="" S3="0" \
		S4="" S5="" S6="0" \
		S7="" S8="" S9="0" \
		S10="" S11="" S12="0" \
		S13="" S14="" S15="0" \
		S16="" S17="" S18="0" \
		S19="" S20="" S21="0" \
		S22="" S23="" S24="0" \
		vlcOptions \
		Eh Em Es \
		line intervals i j k \
		arg s e title files \
		err rc

	mkdir "${tmpDir}"
	vlcOptions=""
	if [ -z "${Debug:=}" ]; then
		vlcOptions="-I dummy"
	elif [ "${Debug}" = "xtrace" ]; then
		vlcOptions="-v"
		set +x
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${tmpDir}log.txt"
		set -x
	fi

	exec > "${msgs}"

	RES="${1:-}${LF}${2:-}${LF}"
	line=0
	for i in $(seq 3 ${#}); do
		arg="$(eval echo "\$${i}")"
		for j in 1 2; do
			s="$(printf '%s\n' "${arg}" | cut -f ${j} -d '-')"
			for k in 1 2 3; do
				let line++,1
				v="$(printf '%s\n' "${s}" | cut -f ${k} -d ':')"
				if printf '%s\n' "${v}" | grep -qsxEe "[[:digit:]]+"; then
					let "v=v,1"
				else
					v=0
				fi
				RES="${v}${LF}"
			done
		done
	done

	VerifyData

	err="y"
	rc=1
	while [ -n "${err}" -o ${rc} -ne 0 ]; do
		rc=0
		RES="$(export DIALOGRC=""
		dialog --stdout --no-shadow --colors \
		--begin 29 0 --title Messages \
		--tailboxbg "${msgs}" 14 172 \
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

	Title="${Title}-${myId}.mpg"
	exec > >(tee /dev/stderr)

	if [ $(echo "${intervals}" | wc -w) -eq 1 ]; then
		VlcGet "${VideoUrl}" "${Title}" $((Is${intervals})) \
		$((Ie${intervals})) $((Il${intervals})) || \
			echo "error in vlc download"
	else
		files="${tmpDir}files.txt"
		: > "${files}"
		err=""
		for i in ${intervals}; do
			title="${tmpDir}${i}.mpg"
			if ! VlcGet "${VideoUrl}" "${title}" $((Is${i})) \
			$((Ie${i})) $((Il${i})); then
				echo "error in vlc download"
				err="y"
			fi
			echo "file '$(basename "${title}")'" >> "${files}"
		done
		if [ -z "${err}" ]; then
			echo "ffmpeg concat" $(cat "${files}")
			if ! ( cd "${tmpDir}"
			ffmpeg -nostdin -hide_banner -y \
			-f concat -safe 0 -i "$(basename "${files}")" \
			-c:v copy "${currDir}${Title}" \
			> "${tmpDir}${Title}.txt" 2>&1
			); then
				echo "error in video concatenation"
			fi
		fi
	fi
	if [ -s "${currDir}${Title}" ]; then
		length=$(_fileSize "${currDir}${Title}")
		echo "length of \"${currDir}${Title}\" is" \
			"$(_thsSep ${length}) bytes"
	else
		echo "error"
	fi
	cat "${msgs}" > /dev/stderr
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber

declare -ar ARGV=("${@}")
readonly ARGC=${#}

Main "${@}"
