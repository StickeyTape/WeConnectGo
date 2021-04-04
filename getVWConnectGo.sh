#!/bin/bash

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}

gen_PKCE() {
      VW_VERIFIER=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 50 | head -n 1`
      VW_CHALLENGE=`echo -n $VW_VERIFIER | shasum -a 256 | cut -d " " -f 1 | xxd -r -p | base64 | tr / _ | tr + - | tr -d =`
}

gen_PKCE

# Main Runtime

if [ "$#" -eq 0 ] ; then
  echo "./getVWConnectGo.sh username password
        username : VW We-Connect Go Username
        password : VW We-Connect Go Password"
else

VW_LOGIN_EMAIL="$(urlencode $1)"
VW_LOGIN_PASSWORD="$2"

VW_CLIENT_ID="ac42b0fa-3b11-48a0-a941-43a399e7ef84@apps_vw-dilab_com"
VW_SCOPE="openid%20profile%20address%20email%20phone"
VW_RESPONSE_TYPE="code"
VW_REDIRECT_URL="vwconnect%3A%2F%2Fde.volkswagen.vwconnect%2Foauth2redirect%2Fidentitykit"
VW_NONCE=`openssl rand -base64 12`
VW_UUID_V4=`uuidgen`

WGET_PARAMS=('-S' '--load-cookies=tmp.cookies' '--header=Content-Type:application/x-www-form-urlencode')

VW_IDENTITY_URL="https://identity.vwgroup.io"

VW_LOGIN_URL="$VW_IDENTITY_URL/oidc/v1/authorize?client_id=$VW_CLIENT_ID&scope=$VW_SCOPE&response_type=$VW_RESPONSE_TYPE&redirect_uri=$VW_REDIRECT_URL&nonce=$VW_NONCE&state=$VW_UUID_v4&code_challenge=$VW_CHALLENGE&code_challenge_method=s256"

curl -s -L -b tmp.cookies -c tmp.cookies -o tmp.login $VW_LOGIN_URL

VW_LOGIN_ACTION=`cat tmp.login | grep action | sed 's#=##' | sed 's#[\ ">]##g' | sed 's#action##g'`
VW_LOGIN_CSRF=`cat tmp.login | grep _csrf | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#["/>]##g'`
VW_LOGIN_RELAYSTATE=`cat tmp.login | grep relayState | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#[/>"]##g'`
VW_LOGIN_HMAC=`cat tmp.login | grep hmac | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#[/>"]##g'`

VW_LOGIN_EMAIL_URL=$VW_IDENTITY_URL$VW_LOGIN_ACTION

POST_DATA="_csrf=$VW_LOGIN_CSRF&relayState=$VW_LOGIN_RELAYSTATE&email=$VW_LOGIN_EMAIL&hmac=$VW_LOGIN_HMAC"

curl -s -L -b tmp.cookies -c tmp.cookies -d "$POST_DATA" -o tmp.login2 $VW_LOGIN_EMAIL_URL

VW_LOGIN_AUTH_ACTION=`cat tmp.login2 | grep action | sed 's#=##' | sed 's#["\ >]##g' | sed 's#action##g'`
VW_LOGIN_AUTH_CSRF=`cat tmp.login2 | grep _csrf | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#["/>]##g'`
VW_LOGIN_AUTH_RELAYSTATE=`cat tmp.login2 | grep relayState | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#[/>"]##g'`
VW_LOGIN_AUTH_HMAC=`cat tmp.login2 | grep hmac | awk '{print $5}' | sed 's#=# #g' | awk '{print $2}' | sed 's#[/>"]##g'`

AUTH_DATA="_csrf=$VW_LOGIN_AUTH_CSRF&relayState=$VW_LOGIN_AUTH_RELAYSTATE&email=$VW_LOGIN_EMAIL&hmac=$VW_LOGIN_AUTH_HMAC&password=$VW_LOGIN_PASSWORD"

VW_LOGIN_AUTH_URL=$VW_IDENTITY_URL$VW_LOGIN_AUTH_ACTION

curl -s -L -D tmp.authheaders -b tmp.cookies -c tmp.cookies -d "$AUTH_DATA" -o tmp.login3 $VW_LOGIN_AUTH_URL
VW_LOGIN_USERID=`cat tmp.authheaders  | grep userId | sed s#.*userId=##g | sed s#\&#\ #g | awk '{print $1}'`

VW_LOGIN_AUTH_CODE=`cat tmp.authheaders | grep code | sed 's#location: vwconnect://de.volkswagen.vwconnect/oauth2redirect/identitykit?code=##g'`

TOKEN_DATA="grant_type=authorization_code&code=$VW_LOGIN_AUTH_CODE&client_id=$VW_CLIENT_ID&redirect_uri=$VW_REDIRECT_URL&code_verifier=$VW_VERIFIER"
VW_LOGIN_TOKEN_URL="https://dmp.apps.emea.vwapps.io/mobility-platform/token"

curl -s -L -D tmp.authtoken -b tmp.cookies -c tmp.cookies -d "$TOKEN_DATA" -o tmp.login4 $VW_LOGIN_TOKEN_URL

VW_LOGIN_TOKEN=`cat tmp.login4`

TOKEN_ID=`echo $VW_LOGIN_TOKEN | jq ".\"id_token\"" | sed 's#\"##g'`
TOKEN_ACCESS=`echo $VW_LOGIN_TOKEN | jq ".\"access_token\"" | sed 's#\"##g'`

# Get Account
ACC_URL="https://customer-profile.apps.emea.vwapps.io/v1/customers/$VW_LOGIN_USERID/personalData"
curl -s -L -H "Authorization: Bearer $TOKEN_ACCESS" $ACC_URL | jq > account.json

# Get Vehicles
CARDATA_URL="https://dmp.apps.emea.vwapps.io/mobility-platform/vehicles"
curl -s -L -H "Authorization: Bearer $TOKEN_ACCESS" -H "dmp-client-info: Android/11.0/VW Connect/App/2.15.11" -H "dmp-api-version: v2.0" $CARDATA_URL | jq > cars.json

rm -Rf tmp.*

echo "Script Completed."

fi
