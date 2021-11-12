AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId')

echo ""
read -p "What would you like this environment to be called? [default: \"dockenv\"]: " env_suffix

# ecsInstanceRole
aws iam create-role \
	--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"","Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
	--role-name $ROLE_NAME

aws iam attach-role-policy \
	--role-name $ROLE_NAME \
	--policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam attach-role-policy \
	--role-name $ROLE_NAME \
	--policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

aws iam create-instance-profile \
	--instance-profile-name $ROLE_NAME

aws iam add-role-to-instance-profile \
	--instance-profile-name $ROLE_NAME \
	--role-name $ROLE_NAME

s3json="{
\"Version\": \"2012-10-17\",
\"Id\": \"s3policy01\",
\"Statement\": [
{
\"Sid\": \"s3statement01\",
\"Effect\": \"Allow\",
\"Action\": [
\"s3:PutObject\",
\"s3:GetObject\",
\"s3:GetBucketLocation\",
\"s3:ListBucket\"
],
\"Resource\": [
\"arn:aws:s3:::$output_bucket/*\",
\"arn:aws:s3:::$output_bucket\",
\"arn:aws:s3:::$input_bucket\",
\"arn:aws:s3:::$input_bucket/*\"
]
}
]
}"

aws iam create-policy \
	--policy-name s3policy \
	--policy-document

# Compute environment
aws batch create-compute-environment \
	--compute-environment-name "dockCE" \
	--service-role "arn:aws:iam:$AWS_ACCOUNT_ID:role/service-role/AWSBatchServiceRole"
	--compute-resources \
		type="SPOT",\
		state="ENABLED",\
		minvCpus=0,\
		maxvCpus=$MAX_CPUS,\
		desiredvCpus=0,\
		instanceTypes="optimal",\
		instanceRole="arn:aws:iam::$AWS_ACCOUNT_ID:instance-profile/ecsInstanceRole",\
		spotIamFleetRole="arn:aws:iam:$AWS_ACCOUNT_ID:role/AmazonEC2SpotFleetTaggingRole",\
		bidPercentage=$BID_PERCENTAGE,\
		ec2KeyPair="$KEY_PAIR"

# Queue
aws batch create-job-queue \
	--job-queue-name "dockQueue" \
	--priority=100 \
	--compute-environment-order \
		order=1,computeEnvironment="dockCE"

# Job definitions and ecs images are created on a region-by-region basis

# ECS image creation
aws ecr create-repository --repository-name dockaws --region $AWS_REGION
ECS_IMAGE_ARN=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/dockaws

docker pull btingle/dockaws:latest
docker tag btingle/dockaws:latest $ECS_IMAGE_ARN

aws ecr get-login-password | docker login --username AWS --password-stdin
docker push $ECS_IMAGE_ARN

# Job definition
jobdef_json="\
{\
\"image\":\"$ECS_IMAGE_ARN\",\
\"vcpus\":1,\
\"memory\":2048,\
\"command\":[],\
\"privileged\":true,\
\"linuxParameters\":{\
\"sharedMemorySize\":6144\
}\
}"

aws batch register-job-definition \
	--job-definition-name "dockJob" \
	--type container \
	--container-properties $jobdef_json