#!/bin/sh
set -e

RANDOM_=${RANDOM_PROG:-random}
NUM_PASSWORDS=${NUM_PASSWORDS:-5}
WORDS_PER_PASSWORD=${WORDS_PER_PASSWORD:-3}
WORD_SEPARATOR=${WORD_SEPARATOR:-,}
DICTIONARY=${DICTIONARY:-"/usr/share/dict/words"}

dictionary_size=$(wc -l "$DICTIONARY" | cut -d ' ' -f 1)

if ! command -v "$RANDOM_" &> /dev/null; then
	echo Random program not found. Path searched: "$RANDOM_"
	exit 1
fi

if test ! -f "$DICTIONARY"; then
	echo Dictionary \""$DICTIONARY"\" does not exist.
	echo Please provide a file with a word list in the DICTIONARY\
             environment variable.
	exit 1
fi

i=1
while [ $i -le "$NUM_PASSWORDS" ]
do
	prefix=$("$RANDOM_" -8 1 0x100000000 | head -c 3)
	words=$("$RANDOM_" "$WORDS_PER_PASSWORD" 1 "$dictionary_size" |
		xargs -I@ sed -n "@{p;q}" "$DICTIONARY")
	echo "$prefix":-$(echo "$words" | tr "\n" "$WORD_SEPARATOR")
	i=$((i+1))
done

