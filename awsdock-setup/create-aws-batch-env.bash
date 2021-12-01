# Author: Benjamin Tingle (ben@tingle.org)
# Figuring out how to configure aws batch can be a struggle, which is why I've created this script
# create-aws-batch-env walks a user step-by-step through the process of creating an environment for aws batch, extracting required information from the user and handling the legwork of creating roles, policies, images, queues, compute environments, jobs etc...
# this script is the culmination of months of trial-and-error experience with aws batch (emphasis on the error)

BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}

### SETUP CONFIGURATION
# this setup script is flexible, and can support setting up aws batch environments for any type of script run from a docker image
# each environment is specific to an aws region- for simplicity's sake you cannot have one environment for multiple regions
# so long as the image script uses s3 buckets for input/output, its batch environment can be configured from this script
# submitting batch jobs for the environment must be handled separately through more specialized submission scripts
# the defaults below set up a batch environment for irwin lab's dockaws image
SETUP_TYPE=${SETUP_TYPE-dockaws} # just a name for the setup configuration
INPUT_BUCKET_DEFAULT=${INPUT_BUCKET_DEFAULT-zinc3d}
INPUT_REQUIRED_ACTIONS=${INPUT_REQUIRED_ACTIONS-"s3:GetObject s3:GetBucketLocation s3:ListBucket"}
OUTPUT_BUCKET_DEFAULT=${OUTPUT_BUCKET_DEFAULT-}
OUTPUT_REQUIRED_ACTIONS=${OUTPUT_REQUIRED_ACTIONS-"s3:GetObject s3:GetBucketLocation s3:ListBucket s3:PutObject"}
ENVIRONMENT_NAME_DEFAULT=${ENVIRONMENT_NAME_DEFAULT-dockenv}
JOB_IMAGE=${JOB_IMAGE-btingle/dockaws:latest}
# Job definition json - ____ECS_IMAGE_ARN____ will be replaced with the ecr container that is created during setup
jobdef_json_default="\
{\
\"image\":\"____ECS_IMAGE_ARN____\",\
\"vcpus\":1,\
\"memory\":2048,\
\"command\":[],\
\"privileged\":true,\
\"linuxParameters\":{\
\"sharedMemorySize\":6144\
}\
}"
JOB_JSON_CONFIG=${JOB_JSON_CONFIG-$jobdef_json_default}
# it should be possible to use this setup script as an iam user, so long as the iam user has the necessary permissions to create roles buckets etc.
### END SETUP CONFIGURATION

AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId')
AWS_ACCOUNT_ARN=$(aws sts get-caller-identity | jq -r '.Arn')

echo "Welcome to the $SETUP_TYPE environment setup script!"
read -p "What would you like this environment to be called? [default: \"$ENVIRONMENT_NAME_DEFAULT\"]: " env_suffix

if [ -z "$env_suffix" ]; then
	env_suffix=$ENVIRONMENT_NAME_DEFAULT
fi

read -p "Which region will this environment be set up for? Current region by default. [default: $(aws configure get region)]: " aws_region

if [ -z $aws_region ]; then
	aws_region=$(aws configure get region)
fi
okay=false
for region in $(aws ec2 describe-regions | jq -r '.Regions[].RegionName'); do
	if [ "$region" = "$aws_region" ]; then
		okay=true
		break
	fi
done
if [ "$okay" = "false" ]; then
	echo "That region does not exist! Try again."
	exit 1
fi

aws configure set region $aws_region

env_suffix=$env_suffix-$aws_region

echo "Your environment's full name is $env_suffix"

ECS_INSTANCE_ROLE_NAME=ecsInstanceRole-$env_suffix

#aws iam get-role --role-name $ECS_INSTANCE_ROLE_NAME > /dev/null 2>&1
#res=$?
#if [ $res -eq 0 ]; then
	#echo "It seems like setup has already been run for this environment."
	# todo: docs...
	#echo "If you cancelled a previous environment setup prematurely, consult the docs for cleanup instructions. It is not strictly necessary to clean up a failed environment (though highly recommended!), you can simply create a new environment under a different name."
	#exit 1
#fi

# ecsInstanceRole    
aws iam create-role \
	--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"","Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
	--role-name $ECS_INSTANCE_ROLE_NAME 1>/dev/null && echo "Created $ECS_INSTANCE_ROLE_NAME role" || echo "Failed to create role- probably because it already exists from a previous run"

aws iam attach-role-policy \
	--role-name $ECS_INSTANCE_ROLE_NAME \
	--policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam attach-role-policy \
	--role-name $ECS_INSTANCE_ROLE_NAME \
	--policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

# our custom ecr policy which allows us to access any repositories this user has created on ecr
aws iam attach-role-policy \
	--role-name $ECS_INSTANCE_ROLE_NAME \
	--policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/ecrPolicy > /dev/null

aws iam create-instance-profile \
	--instance-profile-name $ECS_INSTANCE_ROLE_NAME > /dev/null

aws iam add-role-to-instance-profile \
	--instance-profile-name $ECS_INSTANCE_ROLE_NAME \
	--role-name $ECS_INSTANCE_ROLE_NAME > /dev/null

function create_bucket() {
	return 0
}

function create_bucket_io_policy() {

	io_type=$1
	io_actions=$2
	bucket_default=$3

	while [ -z ]; do

		read -p "Specify the S3 bucket used for $io_type in this environment [default: ${bucket_default-None}]: " bucket

		# we know zinc3d is a public bucket, so we don't need to simulate creating an access policy
		if [ -z $bucket ] && ! [ -z $bucket_default ]; then
			bucket=$bucket_default
		elif [ -z $bucket ] && [ -z $bucket_default ]; then
			echo "Must provide a value!"
			continue
		fi

		aws s3api get-bucket-acl --bucket $bucket > /dev/null 2>&1
		res=$?
		if [ $res -ne 0 ]; then
			read -p "It seems this bucket does not exist yet or has prohibited access, would you like to attempt to create it? [y/n]: " res
			if [ "$res" = "y" ]; then
				create_bucket $bucket
				res=$?
				# if user cancels bucket creation
				if [ $res -ne 0 ]; then
					continue
				fi
			else
				echo "Can't create $io_type policies for a non-existent bucket!"
				continue
			fi
		fi

		S3_POLICY=s3Policy-$io_type-$env_suffix
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
				echo "permissions test: failed to execute $action on $bucket"
			fi

		done

		if [ "$final_result" != "allowed" ]; then
			echo "Unable to create an input policy for this bucket. Alter your permissions for this bucket or select a new one. The prompt will now restart"
		else
			break
		fi

	done
	echo "You have chosen $bucket as your $io_type source for this environment"

	aws iam create-policy \
		--policy-name $S3_POLICY \
		--policy-document $s3iojson > /dev/null || "Looks like the policy for this bucket already exists, probably from a previous run."

	aws iam attach-role-policy \
		--role-name $ECS_INSTANCE_ROLE_NAME \
		--policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$S3_POLICY

}

echo "The following steps create policies allowing jobs to use a bucket for input/output- you have the option to create new buckets for this purpose if you wish. Just enter the new bucket's name!"
create_bucket_io_policy input "$INPUT_REQUIRED_ACTIONS" $INPUT_BUCKET_DEFAULT
create_bucket_io_policy output "$OUTPUT_REQUIRED_ACTIONS" $OUTPUT_BUCKET_DEFAULT

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

MAX_CPUS=$(circular_numerical_prompt "How many CPUS would you like to allocate to this environment at maximum? [default: None]: " "")
# todo: docs...
BID_PERCENTAGE=$(circular_numerical_prompt "What is your bid percentage threshold for spot instances? Consult the docs for more info on this parameter. [default: 100]: " 100)

subnets=$(bash $BINDIR/create-subnets-for-region.bash $aws_region)
securitygroup=$(printf "$subnets" | tail -n 1)
subnets=$(printf "$subnets" | head -n -1)

# Compute environment
compute_env_arn=$(aws batch create-compute-environment \
	--compute-environment-name "${env_suffix}-CE" \
	--type MANAGED \
	--state ENABLED \
	--service-role "arn:aws:iam:$AWS_ACCOUNT_ID:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBash" \
	--compute-resources \
		type="SPOT",\
		minvCpus=0,\
		maxvCpus=$MAX_CPUS,\
		desiredvCpus=0,\
		instanceTypes="optimal",\
		instanceRole="arn:aws:iam::$AWS_ACCOUNT_ID:instance-profile/$ECS_INSTANCE_ROLE_NAME",\
		spotIamFleetRole="arn:aws:iam:$AWS_ACCOUNT_ID:role/AmazonEC2SpotFleetTaggingRole",\
		subnets=$(echo $subnets | tr ' ' ','),\
		bidPercentage=$BID_PERCENTAGE,\
		securityGroupIds=$securitygroup | jq -r '.computeEnvironmentArn')

echo $compute_env_arn

# Queue
aws batch create-job-queue \
	--state ENABLED \
	--job-queue-name "${env_suffix}-Queue" \
	--priority=100 \
	--compute-environment-order \
		order=1,computeEnvironment="$compute_env_arn"

# ECS image creation
image_base_name=$(basename $JOB_IMAGE | cut -d':' -f1)
image_name=$(echo $image_base_name-$env_suffix | tr '[:upper:]' '[:lower:]')

aws ecr create-repository --repository-name $image_name --region $aws_region
ECS_IMAGE_ARN=$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com/$image_name

docker pull $JOB_IMAGE
docker tag $JOB_IMAGE $ECS_IMAGE_ARN

aws ecr get-login-password | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-west-1.amazonaws.com
docker push $ECS_IMAGE_ARN

# Job definition
jobdef_json=$(printf "$JOB_JSON_CONFIG_DEFAULT" | sed "s/____ECS_IMAGE_ARN____/$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com\/$image_name/g")

aws batch register-job-definition \
	--job-definition-name "$SETUP_TYPE-$env_suffix" \
	--type container \
	--container-properties $jobdef_json_default