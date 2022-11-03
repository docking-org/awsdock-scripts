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
[ -z $aws_region ] && aws_region=$(bash $BINDIR/set-aws-region.bash) || true
prompt_or_override "What is the base name for the environment to upload to? [default: None]: " env_suffix env_suffix || true
prompt_or_override "What is the name of the ecr image to be used? This would be the output of upload-docker-ecr.bash. [default: None]: " image_name image_name || true
[ -z $AWS_ACCOUNT_ID ] && AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId') || true

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
			[ -e /tmp/.rememberthis ] && (exasperated=true && rm /tmp/.rememberthis) || exasperated=
			if [ $attempts -eq 0 ]; then
				! [ -z $exasperated ] && echo "Please enter a number using only digits 0-9. Please." 1>&2
				[ -z $exasperated ]   && echo "Please enter a number using only digits 0-9." 1>&2
			elif [ $attempts -eq 1 ]; then
				! [ -z $exasperated ] && echo "Really? This again?"
				[ -z $exasperated ]   && echo "Please enter a number. It's because of people like you that programmers have sleepless nights." 1>&2
			elif [ $attempts -eq 2 ]; then
				! [ -z $exasperated ] && echo "Come back when you're ready to be serious." && exit 1
				echo "Do you get a kick out of this or something? Enter a number!" 1>&2
			elif [ $attempts -eq 3 ]; then
				echo "You're begging for trouble now. Stop it." 1>&2
			elif [ $attempts -eq 4 ]; then
				echo "Last warning..." 1>&2
			elif [ $attempts -eq 5 ]; then
				echo "Fine. Your number is now \"$number\". Let's see how that pans out!" 1>&2
				echo "." > /tmp/.rememberthis
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

SUGGESTED_MAX=$(aws service-quotas list-service-quotas --service-code ec2 | jq -r '.Quotas[] | select(.UsageMetric.MetricDimensions.Class == "Standard/Spot") | .Value')

[ -z $MAX_CPUS ] && MAX_CPUS=$(circular_numerical_prompt "How many CPUS would you like to allocate to this environment at maximum? [suggested: $SUGGESTED_MAX]: " "$SUGGESTED_MAX")

if [ $MAX_CPUS -gt $SUGGESTED_MAX ]; then
	log "Max CPUs value greater than your account quota for spot CPUs!" warning
fi

# todo: docs...
[ -z $BID_PERCENTAGE ] && BID_PERCENTAGE=$(circular_numerical_prompt "What is your bid percentage threshold for spot instances? Consult the docs for more info on this parameter. [default: 100]: " 100)

echo '{"BlockDeviceMappings":[{"DeviceName":"/dev/xvdcz", "Ebs":{"VolumeSize":30, "VolumeType":"gp2"}}]}' > /tmp/ltdata
cmd="aws ec2 create-launch-template --launch-template-name $env_suffix-LT-EBS --launch-template-data file:///tmp/ltdata"
case $(aws_cmd_handler "$cmd" AlreadyExistsException) in
	AlreadyExistsException)
		log "launch template already exists" warning
	;;
	ERROR)
		exit 1
	;;
esac

function get_CE_prop {
	prop=$1
	p=$(aws batch describe-compute-environments --compute-environments $env_suffix-CE | jq -r ".computeEnvironments[] | .$prop")
	echo $p
	return
}
compute_env_arn=$(get_CE_prop computeEnvironmentArn)

subnets=$(bash $BINDIR/create-subnets-for-region.bash $aws_region)
securitygroup=$(printf "$subnets" | tail -n 1)
subnets=$(printf "$subnets" | head -n -1)

ALLOCATION_STRATEGY=${ALLOCATION_STRATEGY-BEST_FIT_PROGRESSIVE}

if [ -z "$compute_env_arn" ]; then

	# Compute environment
	cmd="aws batch create-compute-environment \
		--compute-environment-name "${env_suffix}-CE" \
		--type MANAGED \
		--state ENABLED \
		--compute-resources \
type=SPOT,\
minvCpus=0,\
maxvCpus=$MAX_CPUS,\
tags={\"CEName\":\"${env_suffix}-CE\"},\
allocationStrategy=$ALLOCATION_STRATEGY,\
desiredvCpus=0,\
instanceTypes=optimal,\
instanceRole=arn:aws:iam::$AWS_ACCOUNT_ID:instance-profile/$ECS_INSTANCE_ROLE_NAME,\
spotIamFleetRole=arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEC2SpotFleetTaggingRole,\
subnets=$(echo $subnets | tr ' ' ','),\
bidPercentage=$BID_PERCENTAGE,\
securityGroupIds=$securitygroup,\
launchTemplate={launchTemplateName=$env_suffix-LT-EBS,version=\$Latest}"

	case $(aws_cmd_handler "$cmd") in
		ERROR)
			exit 1
		;;
	esac

	timeout=10
	t=0
	while ! [ "$(get_CE_prop status)" = "VALID" ]; do
		sleep 3
		t=$((t+1))
		if [ $t -gt $timeout ]; then
			log "timed out: failed to detect valid compute environment" error
		fi
	done

else
	log "compute env already exists from previous run, choosing to update it!" warning

	cmd="aws batch update-compute-environment \
		--compute-environment "$compute_env_arn" \
		--state ENABLED \
		--compute-resources \
type=SPOT,\
minvCpus=0,\
maxvCpus=$MAX_CPUS,\
allocationStrategy=SPOT_CAPACITY_OPTIMIZED,\
desiredvCpus=0,\
instanceTypes=optimal,\
instanceRole=arn:aws:iam::$AWS_ACCOUNT_ID:instance-profile/$ECS_INSTANCE_ROLE_NAME,\
subnets=$(echo $subnets | tr ' ' ','),\
bidPercentage=$BID_PERCENTAGE,\
securityGroupIds=$securitygroup,\
launchTemplate={launchTemplateName=$env_suffix-LT-EBS,version=\$Latest}"

	case $(aws_cmd_handler "$cmd") in
		ERROR)
			exit 1
		;;
	esac

	# wait for CE to be valid
	timeout=10
	t=0
	while ! [ "$(get_CE_prop status)" = "VALID" ]; do
		sleep 3
		t=$((t+1))
		if [ $t -gt $timeout ]; then
			log "timed out: failed to detect valid compute environment" error
		fi
	done
fi

compute_env_arn=$(get_CE_prop computeEnvironmentArn)
log $compute_env_arn debug

# Queue
fail=
cmd="aws batch create-job-queue \
	--state ENABLED \
	--job-queue-name "${env_suffix}-Queue" \
	--priority=100 \
	--compute-environment-order \
		order=1,computeEnvironment=$compute_env_arn"

case $(aws_cmd_handler "$cmd" "Object already exists") in
	"Object already exists")
		log "job queue exists from previous run" warning
	;;
	ERROR)
		exit 1
	;;
esac

# Job definition
jobdef_json=$(printf "$JOB_JSON_CONFIG" | sed "s/____ECS_IMAGE_ARN____/$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com\/$image_name/g")

log "$JOB_JSON_CONFIG" debug
log "$jobdef_json" debug

echo "$jobdef_json" > /tmp/jobdef.json

! [ -z "$RETRY_STRATEGY" ] && RETRY_STRATEGY_ARG="--retry-strategy $RETRY_STRATEGY" || RETRY_STRATEGY_ARG=
cmd="aws batch register-job-definition \
	--job-definition-name $env_suffix-jobdef \
	--type container \
	$RETRY_STRATEGY_ARG \
	--container-properties file:///tmp/jobdef.json"

case $(aws_cmd_handler "$cmd") in
	ERROR)
		exit 1
	;;
esac
