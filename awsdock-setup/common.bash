function prompt_or_override {
	prompt=$1
	varname=$2
	overridevarname=$3
	default=$4
	if ! [ -z ${!overridevarname} ]; then
		declare "$varname"="${!overridevarname}"
		return 0
	fi
	while [ -z ${!varname} ]; do
		read -p "$prompt" response
		if [ -z "$response" ]; then
			! [ -z $default ] && response=$default
			[ -z $default ] && continue
		fi
		declare "$varname"="$response"
	done
	return 1
}