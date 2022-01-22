function prompt_or_override {
	prompt=$1
	varname=$2
	overridevarname=$3
	default=$4
	if ! [ -z ${!overridevarname} ]; then
		export "$varname"="${!overridevarname}"
		return 0
	fi
	while [ -z ${!varname} ]; do
		read -p "$prompt" response
		if [ -z "$response" ]; then
			! [ -z "$default" ] && response=$default
			[ -z "$default" ] && continue
		fi
		#echo "test11" 1>&2
		export "$varname"="$response"
	done
	return 1
}

function log {
	msg=$1
	flg=$2
	__LOG_FLAGS=${__LOG_FLAGS-"info error warning"}

	if [[ "$__LOG_FLAGS" == *"$flg"* ]]; then	
		printf "[$(date)][$flg]: $msg\n"
	fi
}

function check_aws_error {
	res=$1
	type=$2
	if [[ "$res" == *"$type"* ]]; then
		exit 0
	fi
	exit 1
}