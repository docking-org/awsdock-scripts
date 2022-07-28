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
		printf "[$(date)][$flg]: $msg\n" 1>&2
	fi
}

function check_aws_error {
	res=$1
	type=$2
	if [[ "$res" == *"$type"* ]]; then
		echo 0
		return
	fi
	echo 1
	return
}

# takes an AWS command and multiple error classes
# the AWS command is run, and its output is grepped for the different error classes
# if no error is detected return nothing and exit with code 0
# if a given error is detected return its name and exit with code 0
# otherwise print the entire error and exit with code 1
function aws_cmd_handler {
	cmd=$1
	warning_classes=${@:2}

	err=
	res=$($cmd 2>&1) || err=t

	if ! [ -z $err ]; then
		for class in $warning_classes; do
			if [ $(check_aws_error "$res" $class) -eq 0 ]; then
				echo $class
				return 0
			fi
		done
		log "$res" error
		echo ERROR
		return 1
	fi

	[ -z $VERBOSE ] || log "$res" info
	echo OK
	return 0
}
