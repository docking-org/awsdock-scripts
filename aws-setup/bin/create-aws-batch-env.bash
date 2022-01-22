# Author: Benjamin Tingle (ben@tingle.org)
# Figuring out how to configure aws batch can be a struggle, which is why I've created this script
# create-aws-batch-env walks a user step-by-step through the process of creating an environment for aws batch, extracting required information from the user and handling the legwork of creating roles, policies, images, queues, compute environments, jobs etc...
# this script is the culmination of months of trial-and-error experience with aws batch (emphasis on the error)
# the script can prompt the user step-by-step through creating an environment, or it can accept config values and run without user input
# Each of the sub-scripts this script calls can also be run standalone similar to this one, either prompting the user or accepting configuration variables
BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

config=$1

set -e # exit on any error code

### SETUP CONFIGURATION
# this setup script is flexible, and can support setting up aws batch environments for any type of script run from a docker image
# each environment is specific to an aws region- for simplicity's sake you cannot have one environment for multiple regions
# this setup script is designed for jobs that use s3 buckets as input/output
# submitting batch jobs for the environment must be handled separately through more specialized submission scripts
# see supersub-aws-dock.bash for an example of this

# Table of Configuration Variables
# note: "override" indicates that this value will bypass an interactive prompt and set the value directly
# name					| override	| description
# CONFIG_NAME			| 			| Name of the configuration setup
# ENV_NAME				| yes		| Name of the environment to create
# ENV_NAME_DEFAULT		|			| Default name if user does not enter anything to prompt
# ENV_BUCKET_CONFIGS	| yes*		| S3 buckets and permissions to include in the environment. *if "prompt(+)" is specified as one of the configs, the user will set the configuration(s) through a prompt instead
# AWS_REGION			| yes		| AWS region this environment will be based in
# MAX_CPUS				| yes		| Maximum number of CPUs active for this environment
# BID_PERCENTAGE		| yes		| maximum % of on-demand price this environment is willing to bid for spot instances with
# JOB_IMAGE_DEFAULT		|			| Default docker image to use for environment if none specified through prompt
# JOB_IMAGE				| yes		| Docker image to use for this environment
# RETRY_STRATEGY		| 			| Retry strategy to use for jobs, e.g retry up to 5 times if job exits with code 1
# JOB_JSON_CONFIG		| 			| Json structure for the job definition, specifies memory, #cpus, vmem, swap, etc. for jobs. Only required variable (others can be set through interactive prompts)
source $config

if [ -z "$JOB_JSON_CONFIG" ]; then
	log "Please specify JOB_JSON_CONFIG in your configuration, this value is required." error
	exit 1
fi

aws configure set output json 1>/dev/null 2>&1
AWS_REGION=$(aws configure get region) || (AWS_REGION=us-west-1 && old_region=)

AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId' 2>/dev/null) || (echo "You must provide your aws account credentials! Try running 'aws configure'" && exit 1)
AWS_ACCOUNT_ARN=$(aws sts get-caller-identity | jq -r '.Arn' 2>/dev/null) || (echo "You must provide your aws account credentials! Try running 'aws configure'" && exit 1)

# initialize environment name
log "{0} Welcome to the $CONFIG_NAME environment setup script!" info
prompt_or_override "What would you like this environment to be called? [default: \"${ENV_NAME_DEFAULT-None}\"]: " env_suffix ENV_NAME $ENV_NAME_DEFAULT || printf ""

# set environment region
export AWS_REGION=$ENV_AWS_REGION
aws_region=$(bash $BINDIR/set-aws-region.bash)
export AWS_REGION=$aws_region

# set environment full name (base name + region)
env_suffix=$env_suffix-$aws_region
log "Your environment's full name is $env_suffix" info

# instance profile creation
export ECS_INSTANCE_ROLE_NAME=ecsInstanceRole-$env_suffix
export AWS_ACCOUNT_ID
log "{1} Creating instance role for env" info
bash $BINDIR/create-env-instance-profile.bash

# bucket config(s) creation
log "{2} The following steps create policies allowing jobs to use s3 bucket(s) for input/output." info
ENV_BUCKET_CONFIGS=${ENV_BUCKET_CONFIGS-prompt+}
for bucket_config in $ENV_BUCKET_CONFIGS; do
	if [ "$bucket_config" = "prompt+" ]; then
		while [ -z ]; do
			bash $BINDIR/create-s3-bucket-policies.bash $env_suffix $aws_region
			read -p "Create another bucket policy? [y/n]" response
			! [ "$response" = "y" ] && break
		done
	fi
	if [ "$bucket_config" = "prompt" ]; then
		bash $BINDIR/create-s3-bucket-policies.bash $env_suffix $aws_region
	else
		bucket=$(echo "$bucket_config" | cut -d':' -f1)
		io_types=$(echo "$bucket_config" | cut -d':' -f2)
		bash $BINDIR/create-s3-bucket-policies.bash $env_suffix $aws_region $io_types $bucket
	fi

done

# docker image upload
export JOB_IMAGE
export JOB_IMAGE_DEFAULT
log "{3} Creating ECR repository from docker image" info
image_name=$(bash $BINDIR/upload-docker-ecr.bash $env_suffix $aws_region)

# compute environment, queue, job definition creation
export RETRY_STRATEGY
export MAX_CPUS
export BID_PERCENTAGE
export JOB_JSON_CONFIG
log "{4} Finalizing AWS batch components" info
bash $BINDIR/create-env-batch-components.bash $env_suffix $aws_region $image_name

log "All done!" info