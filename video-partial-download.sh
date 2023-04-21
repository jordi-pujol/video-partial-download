#!/bin/bash

_unquote() {
	printf '%s\n' "${@}" | \
		sed -re "s/^([\"]([^\"]*)[\"]|[']([^']*)['])$/\2\3/"
}

_line() {
	local line=${1}
	shift
	printf "%s\n" "${@}" | \
		awk -v line="${line}" \
		'NR == line {print; rc=-1; exit}
		END{exit rc+1}'
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

vlc_get() {
	local url="${1}" \
		title="${2}" \
		sTime="${3}" \
		eTime="${4}"

	echo "vlc download \"${url}\" from ${sTime} to ${eTime}"

	vlc ${vlcOptions} \
		--no-one-instance \
		"${url}" \
		--sout "file/${mux}:${title}" \
		--start-time ${sTime} \
		--stop-time ${eTime} \
		--run-time $((4+eTime-sTime)) \
		vlc://quit \
		2>&1 | tee "${title}.txt"

	# ! grep -qsiwEe 'failed or not possible' "${title}.txt" && \

	[ -s "${title}" ] || {
		echo "error in download"
		return 1
	}
}

Main() {
	readonly myId="$(date +%s)"
	readonly tmpDir="./tmp-${myId}/"
	local Url="" Title="" \
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
		Eh Em Es \
		line intervals i \
		s e title files

	mkdir "${tmpDir}"
	Debug="${Debug:-"y"}"
	vlcOptions=""
	if [ -z "${Debug:-}" ]; then
		vlcOptions="-I dummy"
	elif [ "${Debug:-}" = "xtrace" ]; then
		vlcOptions="-v"
		set +x
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${tmpDir}log.txt"
		set -x
	fi

	echo "Messages" > "${tmpDir}msgs.txt"

	Url="${1:-}"
	Title="${2:-}"
	line=0
	for i in $(seq 3 ${#}); do
		arg="$(eval echo "\$${i}")"
		for j in 1 2; do
			s="$(printf '%s\n' "${arg}" | cut -f ${j} -d '-')"
			for k in 1 2 3; do
				let line++,1
				v="$(printf '%s\n' "${s}" | cut -f ${k} -d ':')"
				if printf '%s\n' "${v}" | grep -qsxEe "[[:digit:]]+"; then
					let "S${line}=v,1"
					[ ${k} -eq 3 ] || \
					[ $((S${line})) -gt 0 ] || \
						eval "S${line}="
				else
					eval "S${line}=v"
				fi
			done
		done
	done

	err="y"
	rc=1
	while [ -n "${err}" -o ${rc} -ne 0 ]; do
		rc=0
		export DIALOGRC=""
		RES="$(dialog --stdout --no-shadow --colors \
		--begin 30 0 --title Messages \
		--tailboxbg "${tmpDir}msgs.txt" 14 172 \
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

		Url="$(_line 1 "${RES}")"
		[ -n "${Url}" ] || {
			echo "URL must be specified"
			continue
		}

		Title="$(_line 2 "${RES}")"
		RES="$(printf '%s\n' "${RES}" | \
			sed -re '/^[[:blank:]]*$/s//0/' | \
			tail -n +3)"
		{ echo '#!/bin/sh'
			printf '%s %s %s ' "${0}" "'${Url}'" "'${Title}'"
			printf "'%s:%s:%s-%s:%s:%s' " ${RES}
			echo
		} >> "${tmpDir}cmd.sh"
		echo 'Command'
		printf '%s %s %s ' "${0}" "'${Url}'" "'${Title}'"
		printf "'%s:%s:%s-%s:%s:%s' " ${RES}
		echo

		Info="$(LANGUAGE=C \
			ffmpeg -hide_banner -y -i "${Url}" 2>&1 | \
			sed -n '/^Input #0/,/^At least one/ {/^[^A]/p}')" || :
		if [ -n "${Info}" ]; then
			duration="$(printf '%s\n' "${Info}" | \
				sed -nre '/^[[:blank:]]*Duration: ([[:digit:]]+:[[:digit:]]+:[[:digit:]]+).*/{s//\1/;p;q}')"
		else
			duration=0
			echo "this URL is invalid"
		fi
		echo "video duration is \"${duration}\""
		if [ -s "${Url}" ]; then
			size="$(stat --format %s "${Url}")"
		else
			size="$(LANGUAGE=C \
				wget --verbose --spider -T 7 --no-check-certificate "${Url}" 2>&1 | \
				sed -nre '/^Length: ([[:digit:]]+).*/{s//\1/;p;q}')" || :
		fi
		size=${size:-0}
		echo "video size is $(printf "%'.3d\n" ${size}) bytes"

		if [ -z "${Title}" ]; then
			Title="$(basename "${Url}")"
			Title="${Title%.*}"
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

			if [ ${ss} -lt ${se} ]; then
				intervals="${intervals}${i} "
				let "Is${i}=ss,1"
				let "Ie${i}=se,1"
			elif [ ${ss} -ne 0 -o ${se} -ne 0 ]; then
				err="y"
			fi
			echo "${si}"
		done
		[ -n "${intervals}" ] || {
			echo "have not defined any interval"
			err="y"
		}
	done >> "${tmpDir}msgs.txt"

	Title="${Title}-${myId}.mpg"

	if [ $(echo "${intervals}" | wc -w) -eq 1 ]; then
		vlc_get "${Url}" "${Title}" $((Is${intervals})) $((Ie${intervals})) || {
			echo "error in vlc download"
			exit 1
		}
	else
		files="${tmpDir}files.txt"
		: > "${files}"
		err=""
		for i in ${intervals}; do
			title="${tmpDir}${i}.mpg"
			if ! vlc_get "${Url}" "${title}" $((Is${i})) $((Ie${i})); then
				echo "error in vlc download"
				err="y"
			fi
			echo "file '$(basename "${title}")'" >> "${files}"
		done
		if [ -z "${err}" ]; then
			echo "ffmpeg concat" $(cat "${files}")
			( cd "${tmpDir}"
			ffmpeg -f concat -safe 0 -i "$(basename "${files}")" \
			-c:v copy "../${Title}" ) || {
				echo "error in video concatenation"
				cat "./msgs.txt"
				exit 1
			}
		fi
	fi > /dev/stderr
	cat "${tmpDir}msgs.txt" > /dev/stderr
	echo "Success"
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber

declare -ar ARGV=("${@}")
readonly ARGC=${#}

Main "${@}"
