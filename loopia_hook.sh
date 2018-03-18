#!/usr/bin/env bash

# This is built upon https://gist.github.com/jreinert/49aca3b5f3bf2c5d73d8 by Joakim Reinert, and edited to match the Loopia API
#
# Copyright (c) Anton Andersson. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

API_URL='https://api.loopia.se/RPCSERV'
TMPDIR='/tmp/loopia-acme'

source "$BASEDIR/hooks/loopia/loopia-api-user.auth" # contains user and pass variables

USER=$user
PASS=$pass

build_method_call() {
	local method_name=$1
	shift
	echo -n "<?xml version=\"1.0\"?>"
	echo -n "<methodCall>"
	echo -n "<methodName>$method_name</methodName><params>"

	for param in "$@"; do
		echo -n "$param"
	done
	
	echo -n "</params></methodCall>"
}

build_param() {
	local value=$1
	local type=${2:-string}
	echo -n "<param><value><$type>"
		echo -n "$value"
	echo -n "</$type></value></param>"
}

build_get_records_call() {
	local subdomain=$1
	local domain=$2
	build_method_call 'getZoneRecords' \
		"$(build_param $USER)" \
		"$(build_param $PASS)" \
		"$(build_param $domain)" \
		"$(build_param $subdomain)"
}

build_array_update() {
	local token=$1
	local record_id=${2:-0}
	echo -n '<param>'
		echo -n '<value><struct>'
			echo -n '<member>'
				echo -n "<name>type</name>"
				echo -n "<value><string>TXT</string></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>ttl</name>"
				echo -n "<value><int>300</int></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>rdata</name>"
				echo -n "<value><string>$token</string></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>record_id</name>"
				echo -n "<value><int>$record_id</int></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>priority</name>"
				echo -n "<value><int>1</int></value>"
			echo -n "</member>"
		echo -n "</struct></value>"
	echo -n "</param>"
}

build_update_record_call() {
	local subdomain=$1
	local domain=$2
	local token=$3
	local record_id=${4:-0}
	build_method_call 'updateZoneRecord' \
		"$(build_param $USER)" \
		"$(build_param $PASS)" \
		"$(build_param $domain)" \
		"$(build_param $subdomain)" \
		"$(build_array_update $token $record_id)" 
}


build_array_add() {
	local token=$1
	echo -n '<param>'
		echo -n '<value><struct>'
			echo -n '<member>'
				echo -n "<name>type</name>"
				echo -n "<value><string>TXT</string></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>ttl</name>"
				echo -n "<value><int>300</int></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>rdata</name>"
				echo -n "<value><string>$token</string></value>"
			echo -n "</member>"
			echo -n '<member>'
				echo -n "<name>priority</name>"
				echo -n "<value><int>10</int></value>"
			echo -n "</member>"
		echo -n "</struct></value>"
	echo -n "</param>"
}

build_add_record_call() {
	local subdomain=$1
	local domain=$2
	local token=$3
	build_method_call 'addZoneRecord' \
		"$(build_param $USER)" \
		"$(build_param $PASS)" \
		"$(build_param $domain)" \
		"$(build_param $subdomain)" \
		"$(build_array_add $token)" 
}

build_remove_record_call() {
	local subdomain=$1
	local domain=$2
	local record_id=$3
	build_method_call 'removeZoneRecord' \
		"$(build_param $USER)" \
		"$(build_param $PASS)" \
		"$(build_param $domain)" \
		"$(build_param $subdomain)" \
		"$(build_param $record_id "int")"
}

method_call() {
	local call=$1
	local result=$(curl -s -c "$TMPDIR/cookies" -d "$call" -H 'Content-Type: text/xml' "$API_URL")
	echo "$result"
	echo >&2
	return 1
}

deploy_challenge() {
	local domain=$1
	local token=$2
	echo "$token"
	local result=$(method_call \
		"$(build_add_record_call "_acme-challenge" "$domain" "$token")")
	echo "$result"
}

clean_challenge() {
	local domain=$1

	local result=$(method_call \
		"$(build_get_records_call "_acme-challenge" "$domain")")

	local xpath='//methodResponse//params//member/name[text()="record_id"]/../value/int'
	result=$(xmllint --xpath "$xpath" - <<< $result)
	result=${result//<\/int><int>/" "}
	result=${result//<int>/""}
	result=${result//<\/int>/""}
	local array=($result)

	for i in ${array[@]}
	do
		$(method_call \
			"$(build_remove_record_call "_acme-challenge" "$domain" "$i")")
	done
}

deploy_cert() {
	
	# you don't really need to do this, and could link directly to
	# the symlinks in the dehydrated cert folder, but I like nginx 
	# and to keep my nginx-config-files clean

	local DOMAIN=$1 
	local KEYFILE=$2
	local FULLCHAINFILE=$3
	
	ln -sf "$KEYFILE" "/etc/nginx/ssl/$DOMAIN/privkey.pem"
	ln -sf "$FULLCHAINFILE" "/etc/nginx/ssl/$DOMAIN/fullchain.pem"
	
	service nginx reload
}

invalid_challenge() {
	local RESPONSE=$2
	echo "$RESPONSE"
}

unchanged_cert() {
	local DOMAIN=$1 
	local KEYFILE=$2
	local FULLCHAINFILE=$3
	
	echo "$DOMAIN"
	echo "$KEYFILE"
	echo "$FULLCHAINFILE"
}

mkdir -p "$TMPDIR"

case $1 in
'deploy_challenge')
	deploy_challenge "$2" "$4" 
	sleep 305
	;;
'clean_challenge')
	# this seems to clear the challenge txt before letsencypt have had a chance to validate
	# so I moved the cleaning to when the cert is deployed instead

	# clean_challenge "$2"
	;;
'deploy_cert')
	deploy_cert "$2" "$3" "$5"
	clean_challenge "$2"
	# used to keep track of when a cert was last deployed
	echo "deployed $2" > "$TMPDIR/$2.deploycert"
	;;
'unchanged_cert')
	# used to keep track of when a cert was last requested - to see that cron works as it should
	unchanged_cert "$2" "$3" "$5" > "$TMPDIR/$2.unchanged"
	;;
'invalid_challenge')
	# used to keep track of fails
	invalid_challenge "$2" > "$TMPDIR/$2.fail"
	;;
'request_failure')
# do something
	;;
'generate_csr')
# do something
	;;
'startup_hook')
# do something
	;;
'exit_hook')
# do something
	;;
esac