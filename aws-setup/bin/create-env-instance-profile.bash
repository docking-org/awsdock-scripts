BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

set -e

# ecsInstanceRole    
err=
res=$(aws iam create-role \
	--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"","Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
	--role-name $ECS_INSTANCE_ROLE_NAME 2>&1) || err=t

if ! [ -z $err ]; then
	fail=
	if [ -z $(check_aws_error "$res" EntityAlreadyExists) ]; then
		log "role already exists from previous run!" warning
	else
		fail=t
	fi
	if ! [ -z $fail ]; then
		exit 1
	fi
fi

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

err=
res=$(aws iam create-instance-profile \
	--instance-profile-name $ECS_INSTANCE_ROLE_NAME 2>&1) || err=t

if ! [ -z $err ]; then
	fail=
	if [ -z $(check_aws_error "$res" EntityAlreadyExists) ]; then
        log "instance profile already exists from previous run!" warning
	else
		fail=t
	fi
	if ! [ -z $fail ]; then
		exit 1
	fi
	exit 0
fi

aws iam add-role-to-instance-profile \
	--instance-profile-name $ECS_INSTANCE_ROLE_NAME \
	--role-name $ECS_INSTANCE_ROLE_NAME > /dev/null