BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

set -e

env_suffix=$1
aws_region=$2

# ECS image creation
image_base_name=$(basename $JOB_IMAGE | cut -d':' -f1)
image_name=$(echo $image_base_name-$env_suffix | tr '[:upper:]' '[:lower:]')

export AWS_REGION
[ -z $aws_region ] && aws_region=$(bash $BINDIR/set-aws-region.bash) || printf ""
prompt_or_override "What is the base name for the environment to upload to? [default: None]: " env_suffix env_suffix || printf ""
prompt_or_override "What is the name of the ecr image to be used? This would be the output of upload-docker-ecr.bash. [default: None]: " image_name image_name || printf ""
[ -z $AWS_ACCOUNT_ID ] && AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId') || printf ""

# okay, maybe i had a little too much fun making this. maybe someone will find out the easter egg here and get a kick from it
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
				echo "Please enter a number using only digits 0-9." 1>&2
			elif [ $attempts -eq 1 ]; then
				echo "Please enter a number. It's because of people like you that programmers have sleepless nights." 1>&2
			elif [ $attempts -eq 2 ]; then
				echo "Do you get a kick out of this or something? Enter a number!" 1>&2
			elif [ $attempts -eq 3 ]; then
				echo "You're begging for trouble now. Stop it." 1>&2
			elif [ $attempts -eq 4 ]; then
				echo "Last warning..." 1>&2
			elif [ $attempts -eq 5 ]; then
				echo "Fine. Your number is now \"$number\". Let's see how that pans out!" 1>&2
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

[ -z $MAX_CPUS ] && MAX_CPUS=$(circular_numerical_prompt "How many CPUS would you like to allocate to this environment at maximum? [default: None]: " "")
# todo: docs...
[ -z $BID_PERCENTAGE ] && BID_PERCENTAGE=$(circular_numerical_prompt "What is your bid percentage threshold for spot instances? Consult the docs for more info on this parameter. [default: 100]: " 100)

compute_env_arn=$(aws batch describe-compute-environments | jq -r ".computeEnvironments[] | select(.computeEnvironmentName==\"$env_suffix-CE\") | .computeEnvironmentArn")

if [ -z "$compute_env_arn" ]; then

	subnets=$(bash $BINDIR/create-subnets-for-region.bash $aws_region)
	securitygroup=$(printf "$subnets" | tail -n 1)
	subnets=$(printf "$subnets" | head -n -1)

	echo "$subnets" "$securitygroup" $env_suffix

	# Compute environment
	compute_env_arn=$(aws batch create-compute-environment \
		--compute-environment-name "${env_suffix}-CE" \
		--type MANAGED \
		--state ENABLED \
		--compute-resources \
type="SPOT",\
minvCpus=0,\
maxvCpus=$MAX_CPUS,\
desiredvCpus=0,\
instanceTypes="optimal",\
instanceRole="arn:aws:iam::$AWS_ACCOUNT_ID:instance-profile/$ECS_INSTANCE_ROLE_NAME",\
spotIamFleetRole="arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEC2SpotFleetTaggingRole",\
subnets=$(echo $subnets | tr ' ' ','),\
bidPercentage=$BID_PERCENTAGE,\
securityGroupIds=$securitygroup | jq -r '.computeEnvironmentArn')

	sleep 5

else
	log "compute env already exists from previous run!" warning
fi

log $compute_env_arn debug

# Queue
fail=
res=$(aws batch create-job-queue \
	--state ENABLED \
	--job-queue-name "${env_suffix}-Queue" \
	--priority=100 \
	--compute-environment-order \
		order=1,computeEnvironment="$compute_env_arn" 2>&1) || fail=t

if ! [ -z $fail ]; then
	if [[ "$res" == *"Object already exists"* ]]; then
		log "job queue exists from previous run!" warning 1>&2
	else
		log "$res" error 1>&2
		exit 1
	fi
fi

# Job definition
jobdef_json=$(printf "$JOB_JSON_CONFIG" | sed "s/____ECS_IMAGE_ARN____/$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com\/$image_name/g")

echo "$JOB_JSON_CONFIG"
echo "$jobdef_json"

! [ -z "$RETRY_STRATEGY" ] && RETRY_STRATEGY_ARG="--retry-strategy $RETRY_STRATEGY" || RETRY_STRATEGY_ARG=
aws batch register-job-definition \
	--job-definition-name "$env_suffix-jobdef" \
	--type container \
	$RETRY_STRATEGY_ARG \
	--container-properties "$jobdef_json"