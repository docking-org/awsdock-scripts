BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

set -e

env_suffix=$1
aws_region=$2
export AWS_REGION
[ -z $aws_region ] && aws_region=$(bash $BINDIR/set-aws-region.bash) || printf ""
prompt_or_override "What is the base name for the environment to upload to? [default: None]: " env_suffix env_suffix || printf ""
prompt_or_override "What docker image should this environment use? [default: $JOB_IMAGE_DEFAULT]: " JOB_IMAGE JOB_IMAGE JOB_IMAGE_DEFAULT || printf ""
[ -z $AWS_ACCOUNT_ID ] && AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId') || printf ""

# ECS image creation
image_base_name=$(basename $JOB_IMAGE | cut -d':' -f1)
image_name=$(echo $image_base_name-$env_suffix | tr '[:upper:]' '[:lower:]')

aws ecr create-repository --repository-name $image_name --region $aws_region
ECS_IMAGE_ARN=$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com/$image_name

docker pull $JOB_IMAGE
docker tag $JOB_IMAGE $ECS_IMAGE_ARN

aws ecr get-login-password | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com
docker push $ECS_IMAGE_ARN

echo IMAGE NAME: $image_name 1>&2
echo $image_name