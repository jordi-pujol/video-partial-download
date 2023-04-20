#!/bin/bash

_line() {
	local line=${1}
	shift
	printf "%s\n" "${@}" | \
		awk -v line="${line}" \
		'NR == line {print; rc=-1; exit}
		END{exit rc+1}'
}

vlc_get() {
	local url="${1}" \
		title="${2}" \
		sTime="${3}" \
		eTime="${4}"

	vlc -v "${url}" \
		--sout "file/ts:${title}.mpg" \
		--start-time ${sTime} \
		--run-time $((4+eTime-sTime)) \
		vlc://quit
}

set -o errexit

export DIALOGRC=""
RES="$(dialog --stdout --no-shadow --colors --begin 0 0 --title "VLC download video parts" --colors --form ' Enter Values, press Enter:
____________________ ' 28 172 20 '' 1 1 'URL . . . . . >' 1 1 0 0 '' 1 22 '' 1 22 50 1024 '' 3 1 'Description . ' 3 1 0 0 '' 3 22 '' 3 22 50 1024 '' 5 1 'Interval . . ' 5 1 0 0 '' 5 22 '0' 5 22 4 4 '' 5 26 ':' 5 26 0 0 '' 5 27 '0' 5 27 3 3 '' 5 30 ':' 5 30 0 0 '' 5 31 '0' 5 31 3 3 '' 5 34 '-' 5 34 0 0 '' 5 35 '0' 5 35 4 4 '' 5 39 ':' 5 39 0 0 '' 5 40 '0' 5 40 3 3 '' 5 43 ':' 5 43 0 0 '' 5 44 '0' 5 44 3 3 '' 7 1 'Interval . . ' 7 1 0 0 '' 7 22 '0' 7 22 4 4 '' 7 26 ':' 7 26 0 0 '' 7 27 '0' 7 27 3 3 '' 7 30 ':' 7 30 0 0 '' 7 31 '0' 7 31 3 3 '' 7 34 '-' 7 34 0 0 '' 7 35 '0' 7 35 4 4 '' 7 39 ':' 7 39 0 0 '' 7 40 '0' 7 40 3 3 '' 7 43 ':' 7 43 0 0 '' 7 44 '0' 7 44 3 3 '' 9 1 'Interval . . ' 9 1 0 0 '' 9 22 '0' 9 22 4 4 '' 9 26 ':' 9 26 0 0 '' 9 27 '0' 9 27 3 3 '' 9 30 ':' 9 30 0 0 '' 9 31 '0' 9 31 3 3 '' 9 34 '-' 9 34 0 0 '' 9 35 '0' 9 35 4 4 '' 9 39 ':' 9 39 0 0 '' 9 40 '0' 9 40 3 3 '' 9 43 ':' 9 43 0 0 '' 9 44 '0' 9 44 3 3 '' 11 1 'Interval . . ' 11 1 0 0 '' 11 22 '0' 11 22 4 4 '' 11 26 ':' 11 26 0 0 '' 11 27 '0' 11 27 3 3 '' 11 30 ':' 11 30 0 0 '' 11 31 '0' 11 31 3 3 '' 11 34 '-' 11 34 0 0 '' 11 35 '0' 11 35 4 4 '' 11 39 ':' 11 39 0 0 '' 11 40 '0' 11 40 3 3 '' 11 43 ':' 11 43 0 0 '' 11 44 '0' 11 44 3 3)" || \
	exit 0

Url="$(_line 1 "${RES}")"
Title="$(_line 2 "${RES}")"
l=3
m=0
for i in $(seq 1 4); do
	Sh="$(_line ${l} "${RES}")"
	let l++,1
	Sm="$(_line ${l} "${RES}")"
	let l++,1
	Ss="$(_line ${l} "${RES}")"
	let l++,1
	Eh="$(_line ${l} "${RES}")"
	let l++,1
	Em="$(_line ${l} "${RES}")"
	let l++,1
	Es="$(_line ${l} "${RES}")"
	let l++,1
	[ -n "${Sh}" -a -n "${Sm}" -a -n "${Ss}" ] && \
	[ ${Sh} -ge 0 -a ${Sm} -ge 0 -a ${Ss} -ge 0 ] && \
	[ -n "${Eh}" -a -n "${Em}" -a -n "${Es}" ] && \
	[ ${Eh} -ge 0 -a ${Em} -ge 0 -a ${Es} -ge 0 ] || \
		break
	s=""
	let "s=(((Sh*60)+Sm)*60)+Ss" || \
	[ "${s}" = 0 ] || \
		break
	e=""
	let "e=(((Eh*60)+Em)*60)+Es" || \
		break
	[ ${s} -lt ${e} ] || \
		break
	let S${i}=${s}
	let E${i}=${e}
	m=${i}
done

[ ${m} -gt 0 ] || \
	exit 1

if [ ${m} -eq 1 ]; then
	vlc_get "${Url}" "${Title}" $((S${m})) $((E${m}))
else
	for i in $(seq 1 ${m}); do
		vlc_get "${Url}" "${Title}-${i}" $((S${i})) $((E${i}))
	done
	ffmpeg $(for i in $(seq 1 ${m}); do
		printf '-i "%s" ' "${Title}-${i}.mpg"
		done) \
		"${Title}.mpg"
fi


		#filess=""
			#filess="${filess} ${title}"
		#vlc ${filess} \
		#	--sout "#gather:std{access=file,mux=${mux},dst=vlc${myPid}-all.mpg}" \
		#	--no-sout-all --sout-keep vlc://quit
