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