AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId')

# Service roles
service_roles="autoscaling batch spot spotfleet ecs rds"
for service in $service_roles; do
	aws iam create-service-linked-role --aws-service-name $service.amazonaws.com
done

aws iam create-policy \
	--policy-name ecrPolicy \
	--policy-document '{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Action": ["ecr:BatchCheckLayerAvailability","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:GetAuthorizationToken"],"Resource": ["*"]}]}'
## custom policies later...

# Spot Fleet
aws iam create-role \
	--role-name AmazonEC2SpotFleetTaggingRole \
	--assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"","Effect":"Allow","Principal":{"Service":"spotfleet.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \

aws iam attach-role-policy \
	--policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole \
	--role-name AmazonEC2SpotFleetTaggingRole

# Batch Service Role
aws iam create-role \
	--role-name AWSBatchServiceRole \
	--path "/service-role/" \
	--assume-role-policy-document '{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Principal": {"Service": "batch.amazonaws.com"},"Action": "sts:AssumeRole"}]}' \

aws iam attach-role-policy \
	--role-name AWSBatchServiceRole	\
	--policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole
