function circular_numerical_prompt {
	prompt=$1
	default=$2
	attempts=0
	while [ -z ]; do
		read -p "$prompt" number
		if [ -z $default ] && [ -z $number ]; then
			echo "Please enter a number- there is no default value." 1>&2
			continue
		elif [ -z $number ]; then
			echo $default
			return
		fi
		re='^[0-9]+$'
		if ! [[ $number =~ $re ]] ; then
			if [ $attempts -eq 0 ]; then
				echo "Please enter a number. It's because of people like you that programmers have sleepless nights." 1>&2
			elif [ $attempts -eq 1 ]; then
				echo "Do you get a kick out of this or something? Enter a number!" 1>&2
			elif [ $attempts -eq 2 ]; then
				echo "You're begging for trouble now. Stop it." 1>&2
			elif [ $attempts -eq 3 ]; then
				echo "Last warning..." 1>&2
			elif [ $attempts -eq 4 ]; then
				echo "Fine. Your number is now $number. Let's see how that pans out!" 1>&2
				echo $number
				return
			fi
			attempts=$((attempts+1))
			continue
		fi
		break
	done
	if [ $attempts -gt 1 ]; then
		echo "That wasn't so hard, now was it?" 1>&2
	fi
	echo $number
}

MAX_CPUS=$(circular_numerical_prompt "How many CPUS would you like to allocate to this environment at maximum? [default: None]: " "")
echo $MAX_CPUS
# todo: docs...
BID_PERCENTAGE=$(circular_numerical_prompt "What is your bid percentage threshold for spot instances? Consult the docs for more info on this parameter. [default: 100]: " 100)
echo $BID_PERCENTAGE
