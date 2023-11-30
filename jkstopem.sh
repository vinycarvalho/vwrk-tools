#!/bin/bash

keytool_cmd=keytool
openssl_cmd=openssl

if ! options=$(getopt -o c:k:p: -l cert:,keystore:,pass: -- "$@"); then
	exit 1
fi

set -- $options

while [ $# -gt 0 ]; do
	case $1 in
		-c|--cert) 
			cert_path="$2";
			shift
			;;
		-k|--keystore) 
			jks_keystore="$2";
			shift
			;;
		-p|--pass)
			jks_pass="$2"
			shift
			;;
		--keytool)
			keytool_cmd="$2"
			shift
			;;
		--openssl)
			openssl_cmd="$2"
			shift
			;;
		(--)
			shift;
			break
			;;
		(-*)
			echo "$0: error - unrecognized option $1" 1>&2;
			exit 1
			;;
		(*)
			break
			;;
	esac

	shift
done

if ! (which $keytool_cmd > /dev/null); then
	echo "Command $keytool_cmd not found"
	exit
fi

if ! (which $openssl_cmd > /dev/null); then
	echo "Command $openssl_cmd not found"
	exit
fi

if ! ($keytool_cmd -v -keystore $jks_keystore -storepass "$jks_pass" -list >&- 2>&-); then
	echo "Fail to get certicate list of keystore $jks_keystore"
	exit
fi

rm -f $cert_path/cert.pem $cert_path/private.key

while read line; do
	if grep -Eq "^Alias name:" <<< $line; then
		let cert_num++
		cert_alias[$cert_num]=$(sed  "s/^Alias name: //g" <<< $line)
		echo "Certificate [$cert_num]"
		echo "$line"
	else
		echo -e "$line\n"
	fi
	
done <<< "$($keytool_cmd -v -keystore $jks_keystore -storepass "$jks_pass" -list 2>&- | grep -E "^(Owner|Alias name):")"

read -p "Select certificate [1-${#cert_alias[@]}]: " cert_choiced

echo ${cert_alias[$cert_choiced]}

[[ -d $cert_path ]] || mkdir $cert_path

$keytool_cmd -importkeystore -srckeystore $jks_keystore -srcstorepass $jks_pass -destkeystore $cert_path/cert.p12 -deststoretype PKCS12 -srcalias "${cert_alias[$cert_choiced]}" -deststorepass $jks_pass -destkeypass $jks_pass
$openssl_cmd pkcs12 -in $cert_path/cert.p12 -nokeys -out $cert_path/cert.pem -passin pass:$jks_pass
$openssl_cmd pkcs12 -in $cert_path/cert.p12 -nodes -nocerts -out $cert_path/private.key -passin pass:$jks_pass

rm -f $cert_path/cert.p12

