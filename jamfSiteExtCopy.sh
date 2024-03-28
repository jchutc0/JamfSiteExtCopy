#!/bin/bash

# default values
#### #### #### #### #### #### #### #### #### #### 
declare scriptname=$(basename "$0")
declare client_id
declare client_secret
declare servername
declare token
declare tokenExpire
declare -a computerList
declare -a mobileList

## debug
#### #### #### #### #### #### #### #### #### #### 
# $1 = message to print
# scriptname - basename of the script
# debug_mode - set (true) if script sends debug messages
debug() {
	if [ -z "${debug_mode+x}" ]; then return; fi
	local timestamp=$(date +%Y-%m-%d\ %H:%M:%S)    
	echo "${timestamp} [${scriptname}]:  $@" 1>&2
}

## usage
#### #### #### #### #### #### #### #### #### #### 
# Exits the program with an error message
exitWithError() {
	local error_message="$1"
	debug "[ERROR] ${error_message}"
	echo "Error: ${error_message}" 1>&2
	exit 1
}

## usage
#### #### #### #### #### #### #### #### #### #### 
# prints the program usage
usage() {
	echo "Usage"
	echo "    ${scriptname} [-v] [-c] [-m] [-s <server name>] [-u <client id>] [-p <client secret>]"
	echo ""
	echo "Downloads computer and mobile devices information from a Jamf Pro server API and sets the 'Jamf Site' extension attribute to the value of the item's Jamf site if that is not already set.'"
	echo ""
	echo "Uses API keys which can be set up through the Jamf Pro server (curently under Settings -> System -> API Roles and Clients). If the server name and/or credentials are not specified, the script will prompt for them."
	echo ""
	echo "The role assigned to the API client ID must have access to read and update Computers, read and update Mobile Devices, and update Users, or else the Jamf Pro server will return an authorization error for some operations. "
	echo ""
	echo "Options"
	echo "    -s <server name>"
	echo "        Specify the server name (URL) of the Jamf Pro server"
	echo "    -u <client id>"
	echo "        Specify the client ID for the Jamf Pro server API"
	echo "    -p <client secret>"
	echo "        Specify the client secret for the Jamf Pro server API"
	echo "    -c"
	echo "        Skip computers (only check mobile devices) mode"
	echo "    -m"
	echo "        Skip mobile devices (only check computers) mode"
	echo "    -v"
	echo "        Sets verbose (debug) mode"
}

## usageError
#### #### #### #### #### #### #### #### #### #### 
# prints an error showing the program usage
usageError() {
	usage 
	echo ""
	exitWithError "ERROR: $1"
}

## checkToken
#### #### #### #### #### #### #### #### #### #### 
# checks for a valid token
checkToken() {
	if ! local currentTime=$(/bin/date +%s); then
		exitWithError "Unable to get the current date."
	fi
	debug "Checking token for $currentTime..."
	if [ -n "${token}" ] && [ "$currentTime" -lt "$tokenExpire" ]; then
		debug "    Valid token"
		return 0
	fi
	debug "    Invalid token"
	return 1
}

## requestToken
#### #### #### #### #### #### #### #### #### #### 
# requests an API token from the Jamf server
requestToken() {
	local webdata
	local expiresIn
	local expireBuffer=10
	
	if checkToken; then return; fi
	debug "Getting new token"
	local tokenUrl="${servername}/api/oauth/token"
	debug "  Using URL $tokenUrl"
	if ! webdata=$(curl -s --request POST "$tokenUrl" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=${client_id}" \
        --data-urlencode "client_secret=${client_secret}"); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		exitWithError "Unable to connect to server. See detail above."
    fi
	if ! token=$(printf "%s" "${webdata}" | /usr/bin/plutil -extract "access_token" raw -o - -); then
		debug "Token data error. Exiting."
		echo "Server response: ${webdata}"
		exitWithError "Unable to extract token data"
	fi
	# debug "Webdata: $webdata"
	# expires_in":299
	if ! expiresIn=$(printf "%s" "${webdata}" | /usr/bin/plutil -extract "expires_in" raw -o - -); then
		debug "Token expire data error. Exiting."
		echo "Server response: ${webdata}"
		exitWithError "Unable to extract token expiration data"
	fi
	debug "Setting token expire to $expiresIn"
	if ! tokenExpire=$(/bin/date -v+${expiresIn}S -v-${expireBuffer}S +%s ); then
		debug "Unable to set token expire time. Exiting."
		exitWithError "Unable to set token expire time."
	fi
	if ! checkToken; then 
		debug "Token validation error. Exiting."
		echo "Server response: ${webdata}"
		exitWithError "Unable to get token data"
	fi
	debug "Bearer Token: $token"
	debug "Token Expire: $tokenExpire"
}

## getComputerList
#### #### #### #### #### #### #### #### #### #### 
# Download current list of computers through API
getComputerList() {
	local compUrl="${servername}/JSSResource/computers"
	local webdata
	requestToken
	debug "  using URL $compUrl"
	if ! webdata=$(curl -s --request GET "$compUrl" \
		-H "Authorization: Bearer $token" \
		-H 'accept: application/json'); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		exitWithError "Unable to get computer data. See detail above."
	fi
	IFS=$'\r\n' \
	GLOBIGNORE='*' \
	computerList=($(echo "$webdata" | /usr/local/bin/jq '[.computers[].id][]'))
	debug "---"
	debug "computerList"
	debug "${computerList[@]}"
# 	for i in "${computerList[@]}"; do
# 		debug "$i"		
# 	done
	debug "---"
} # getComputerList

## checkComputer
#### #### #### #### #### #### #### #### #### #### 
## Check a single computer object to see if the site matches the extension attribute
checkComputer() {
	local id="$1"
	local compUrl="${servername}/JSSResource/computers/id/${id}"
	local siteJq='.computer.general.site.name'
	local extensionJq='.computer.extension_attributes[] | select(.name == "Jamf Site") | .value'
	local webdata
	local siteName
	local extensionName
	requestToken
	debug "  using URL $compUrl"
	if ! webdata=$(curl -s --request GET "$compUrl" \
		-H "Authorization: Bearer $token" \
		-H 'accept: application/json'); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		exitWithError "Unable to get computer data for ID $id. See detail above."
	fi
	# Get Site Name
	if ! siteName=$(echo $webdata | /usr/local/bin/jq -r "$siteJq"); then
		echo "Detail: ${webdata}"
		exitWithError "Unable to get computer site name from web data"
	fi
	# Get Extension Attribute
	if ! extensionName=$(echo $webdata | /usr/local/bin/jq -r "$extensionJq"); then
		echo "Detail: ${webdata}"
		exitWithError "Unable to get computer site name extension from web data"
	fi
	debug "Comparing $siteName to $extensionName"
	if [ ! "$siteName" == "$extensionName" ]; then
		updateComputer "$id" "$siteName"
		return 1
	fi
	return 0
}

## updateComputer
#### #### #### #### #### #### #### #### #### #### 
## Sets a computer object to have the site match the extension attribute
updateComputer() {
	local id="$1"
	local site="$2"
	local url="${servername}/JSSResource/computers/id/${id}"
	requestToken
	debug "Updating computer ID $id to site $site using URL $url"
	xml="<computer><extension_attributes><extension_attribute><name>Jamf Site</name><value>${site}</value></extension_attribute></extension_attributes></computer>"
	debug "$xml"
	if ! webdata=$(curl -s --request PUT "$url" \
		-H "Authorization: Bearer $token" \
		-H "Content-Type: application/xml" \
		-d "$xml"); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		echo "computer ID $id :: site $site :: using URL $url"
		echo "xml: $xml"
		exitWithError "Unable to set computer site. See detail above."
	fi
	debug "$webdata"
	debug "Data sent successfully"
}

## getMobileList
#### #### #### #### #### #### #### #### #### #### 
# Download current list of mobile devices through API
getMobileList() {
	local url="${servername}/JSSResource/mobiledevices"
	local webdata
	requestToken
	debug "  using URL $url"
	if ! webdata=$(curl -s --request GET "$url" \
		-H "Authorization: Bearer $token" \
		-H 'accept: application/json'); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		exitWithError "Unable to get mobile device data. See detail above."
	fi
	IFS=$'\r\n' \
	GLOBIGNORE='*' \
	mobileList=($(echo "$webdata" | /usr/local/bin/jq '[.mobile_devices[].id][]'))
	debug "---"
	debug "mobileList"
	debug "${mobileList[@]}"
	debug "---"
} # getMobileList

## checkMobile
#### #### #### #### #### #### #### #### #### #### 
## Check a single mobile device object to see if the site matches the extension attribute
checkMobile() {
	local id="$1"
	local url="${servername}/JSSResource/mobiledevices/id/${id}"
	local siteJq='.mobile_device.general.site.name'
	local extensionJq='.mobile_device.extension_attributes[] | select(.name == "Jamf Site") | .value'
	local webdata
	local siteName
	local extensionName
	requestToken
	debug "  using URL $url"
	if ! webdata=$(curl -s --request GET "$url" \
		-H "Authorization: Bearer $token" \
		-H 'accept: application/json'); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		exitWithError "Unable to get mobile data for ID $id. See detail above."
	fi
	# Get Site Name
	if ! siteName=$(echo $webdata | /usr/local/bin/jq -r "$siteJq"); then
		echo "Detail: ${webdata}"
		exitWithError "Unable to get mobile device site name from web data"
	fi
	# Get Extension Attribute
	if ! extensionName=$(echo $webdata | /usr/local/bin/jq -r "$extensionJq"); then
		echo "Detail: ${webdata}"
		exitWithError "Unable to get mobile device site name extension from web data"
	fi
	debug "Comparing $siteName to $extensionName"
	if [ ! "$siteName" == "$extensionName" ]; then
		updateMobile "$id" "$siteName"
		return 1
	fi
	return 0
} # checkMobile

## updateMobile
#### #### #### #### #### #### #### #### #### #### 
## Sets a mobile device object to have the site match the extension attribute
updateMobile() {
	local id="$1"
	local site="$2"
	local url="${servername}/JSSResource/mobiledevices/id/${id}"
	requestToken
	debug "Updating mobile device ID $id to site $site using URL $url"
	xml="<mobile_device><extension_attributes><extension_attribute><name>Jamf Site</name><value>${site}</value></extension_attribute></extension_attributes></mobile_device>"
	debug "$xml"
	if ! webdata=$(curl -s --request PUT "$url" \
		-H "Authorization: Bearer $token" \
		-H "Content-Type: application/xml" \
		-d "$xml"); then
		debug "Connection error. Exiting."
		echo "Detail: ${webdata}"
		echo "computer ID $id :: site $site :: using URL $url"
		echo "xml: $xml"
		exitWithError "Unable to set computer site. See detail above."
	fi
	debug "$webdata"
	debug "Data sent successfully"
}

## main
#### #### #### #### #### #### #### #### #### #### 
echo "$scriptname"

## Checking dependencies
if ! /usr/local/bin/jq --version &>/dev/null; then 
	exitWithError "Requires jq to be installed. See https://github.com/jqlang/jq"
fi


# Parse arguments
while getopts "cmhp:s:u:v" flag
do
	case "${flag}" in
		c) no_computer_mode=true;;
		m) no_mobile_mode=true;;
		h) usage && exit 0;;
		p) client_secret="${OPTARG}";;
		s) servername="${OPTARG}";;
		u) client_id="${OPTARG}";;
		v) debug_mode=true;;
		:) usageError "-${OPTARG} requires an argument.";;
		?) usage && exit 0;;
	esac
done
## Remove the options from the parameter list
debug "Argument List:"
debug "$@"
shift $((OPTIND-1))
if [ ${#} -ne 0 ]; then
	usageError "Invalid argument"
fi

debug "Checking for server name"
while [ -z "${servername}" ]; do
	read -r -p "Please enter the URL to the Jamf Pro server (starting with https): " servername
done

debug "Checking for client_id"
while [ -z "${client_id}" ]; do
	read -r -p "Please enter a Jamf API client ID: " client_id
done

debug "Checking for client_secret"
while [ -z "${client_secret}" ]; do
	read -r -s -p "Please enter a Jamf API client secret: " client_secret
	echo ""
done


if [ -z "${no_computer_mode+x}" ]; then
	debug "Getting Jamf computers list"
	getComputerList
fi

computerCount=${#computerList[@]}
if [ $computerCount -gt 0 ]; then
	echo "Found $computerCount computer(s)"
	counter=1
	for i in "${computerList[@]}"; do
		printf "%s" "Processing computer $i ($counter / $computerCount)... "
		if checkComputer "$i"; then
			echo "(correct)"
		else
			echo "(updated)"
		fi
		counter=$((counter + 1))
	done
fi

if [ -z "${no_mobile_mode+x}" ]; then
	debug "Getting Jamf mobile devices list"
	getMobileList
fi

mobileCount=${#mobileList[@]}
if [ $mobileCount -gt 0 ]; then
	echo "Found $mobileCount mobile device(s)"
	counter=1
	for i in "${mobileList[@]}"; do
		printf "%s" "Processing device $i ($counter / $mobileCount)... "
		if checkMobile "$i"; then
			echo "(correct)"
		else
			echo "(updated)"
		fi
		counter=$((counter + 1))
	done
fi

debug "Exiting."