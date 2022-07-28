BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

# ecsInstanceRole
echo '{"Version":"2012-10-17","Statement":[{"Sid":"","Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /tmp/instancerole_policy.json
cmd="aws iam create-role --assume-role-policy-document file:///tmp/instancerole_policy.json --role-name $ECS_INSTANCE_ROLE_NAME"
case $(aws_cmd_handler "$cmd" EntityAlreadyExists) in
	EntityAlreadyExists)
		log "role already exists from previous run!" warning
	;;
	ERROR)
		exit 1
	;;
esac

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

cmd="aws iam create-instance-profile --instance-profile-name $ECS_INSTANCE_ROLE_NAME"
case $(aws_cmd_handler "$cmd" EntityAlreadyExists) in
	EntityAlreadyExists)
		log "instance profile already exists from previous run!" warning
	;;
	ERROR)
		exit 1
	;;
esac

cmd="aws iam add-role-to-instance-profile --instance-profile-name $ECS_INSTANCE_ROLE_NAME --role-name $ECS_INSTANCE_ROLE_NAME"
case $(aws_cmd_handler "$cmd" LimitExceeded) in
	LimitExceeded)
		true
	;;
	ERROR)
		exit 1
	;;
esac