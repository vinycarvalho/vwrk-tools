#!/bin/bash

keytool_cmd=/usr/java/jdk1.6.0_18/bin/keytool
openssl_cmd=openssl
cert_path=/etc/pki/tls/certs/ptu
jks_keystore="/cloud/totvs/foundation/jboss-4.2.3.GA/server/ptu/conf/cert.javaks"

echo "
   _____      _                  _____          _
  / ____|    | |                / ____|        | |
 | (___   ___| |_ _   _ _ __   | |     ___ _ __| |_
  \___ \ / _ \ __| | | | '_ \  | |    / _ \ '__| __|
  ____) |  __/ |_| |_| | |_) | | |___|  __/ |  | |_
 |_____/ \___|\__|\__,_| .__/   \_____\___|_|   \__|
                       | |
                       |_|
"

read -sp "Keystore password: " jks_pass
echo
echo

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

