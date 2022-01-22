BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

set -e

env_suffix=$1
aws_region=$2
io_types_default=$3
bucket_default=$4

export AWS_REGION
[ -z $aws_region ] && aws_region=$(bash $BINDIR/set-aws-region.bash) || printf ""
prompt_or_override "What is the base name for the environment to upload to? [default: None]: " env_suffix env_suffix || printf ""
[ -z $AWS_ACCOUNT_ID ] && AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId') || printf ""

while [ -z ]; do
	DEFAULT_USED=
	FAIL=

	prompt_or_override "What bucket would you like to attach to this environment? " "bucket" "bucket_default" && DEFAULT_USED=TRUE || printf ""
	prompt_or_override "Which action(s) would you like to perform on this bucket? Choose from input/output, if using multiple separate by commas. " "io_types" "io_types_default" && DEFAULT_USED=TRUE || printf ""

	log $bucket debug
	res=0
	aws s3api get-bucket-acl --bucket $bucket > /dev/null 2>&1 || res=1
	if [ $res -ne 0 ]; then
		log "Can't create $io_types policies for a non-existent bucket!" error
		if [ -z $DEFAULT_USED ]; then
			log "Restarting prompt" warning
			continue
		else
			log "Exiting bucket creation" error
			FAIL=TRUE
			break
		fi
	fi

	io_actions="s3:ListBucket s3:GetBucketLocation"
	for io_type in $(printf $io_types | tr ',' '\n'); do
		if [ "$io_type" = "input" ]; then
			io_actions="$io_actions s3:GetObject "
		elif [ "$io_type" = "output" ]; then
			io_actions="$io_actions s3:PutObject "
		fi
	done
	io_actions=$(echo "$io_actions" | head -c-2)

	io_types_identifier=$(printf $io_types | tr ',' '-')

	S3_POLICY=s3Policy-$io_types_identifier-$env_suffix
	S3_POLICY_NODASH=$(printf $S3_POLICY | sed 's/-//g')

	s3iojson="{\"Version\":\"2012-10-17\",\"Id\":\"$S3_POLICY_NODASH\",\"Statement\":[{\"Sid\":\"${S3_POLICY_NODASH}statement\",\"Effect\":\"Allow\",\"Action\":["
	# append each of the required actions to the policy
	for action in $io_actions; do
		s3iojson="$s3iojson""\"$action\","
	done
	s3iojson=$(echo "$s3iojson" | head -c-2) # cut off trailing comma
	s3iojson="$s3iojson""],\"Resource\":[\"arn:aws:s3:::$bucket/*\",\"arn:aws:s3:::$bucket\"]}]}"

	final_result="allowed"
	# we simulate what would happen if we attached this policy to our ecsInstanceRole and performed the various actions we require of it
	# each action yields a result- if any result is negative, we cannot use this policy to access the bucket
	for eval_result in $(aws iam simulate-principal-policy \
		--policy-source-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/$ECS_INSTANCE_ROLE_NAME \
		--policy-input-list "$s3iojson" \
		--action-names $io_actions\
		--resource-arns "arn:aws:s3:::$bucket/*" | jq -r '.EvaluationResults[] | .EvalDecision + "____" + .EvalActionName'); do

		result=$(echo $eval_result | sed 's/____/ /g' | cut -d' ' -f1)
		action=$(echo $eval_result | sed 's/____/ /g' | cut -d' ' -f2)

		if [ "$result" != "allowed" ]; then
			final_result="failed"
			log "permissions test: failed to execute $action on $bucket" error
		fi

	done

	if [ "$final_result" != "allowed" ]; then
		if [ -z $DEFAULT_USED ]; then
			log "Unable to create policies for this bucket. Alter your permissions for this bucket or select a new one. The prompt will now restart." warning
		else
			log "Unable to create policies for this bucket. Alter your permissions for this bucket or select a new one. Exiting bucket policy creation." error
			FAIL=TRUE
			break
		fi
	else
		break
	fi

done
if ! [ -z $FAIL ]; then
	exit 1
fi

log "bucket:$bucket, io_types:$io_types" info

err=
res=$(aws iam create-policy \
	--policy-name $S3_POLICY \
	--policy-document $s3iojson 2>&1) || err=t

if ! [ -z $err ]; then
	fail=
	if [ -z $(check_aws_error "$res" EntityAlreadyExists) ]; then
		log "policy already exists from previous run!" warning
	else
		fail=t
	fi
	if ! [ -z $fail ]; then
		log "$res" error
		exit 1
	fi
fi

aws iam attach-role-policy \
	--role-name $ECS_INSTANCE_ROLE_NAME \
	--policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$S3_POLICY