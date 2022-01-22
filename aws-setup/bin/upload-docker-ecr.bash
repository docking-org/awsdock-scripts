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
prompt_or_override "What docker image should this environment use? [default: $JOB_IMAGE_DEFAULT]: " JOB_IMAGE JOB_IMAGE $JOB_IMAGE_DEFAULT || printf ""
[ -z $AWS_ACCOUNT_ID ] && AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.UserId') || printf ""

# ECS image creation
image_base_name=$(basename $JOB_IMAGE | cut -d':' -f1)
image_name=$(echo $image_base_name-$env_suffix | tr '[:upper:]' '[:lower:]')

fail=
res=$(aws ecr create-repository --repository-name $image_name --region $aws_region 2>&1) || fail=t
if ! [ -z $fail ]; then
	if [[ "$res" == *"RepositoryAlreadyExistsException"* ]]; then
		log "ecr repository already exists, going to update it instead" info
	else
		log "unexpected error happened when creating ecr repository" error
		log "$res" error
		log "exiting with failure..." error
		exit 1
	fi
fi
ECS_IMAGE_ARN=$AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com/$image_name

fail=
docker pull $JOB_IMAGE 1>&2 || (log "failed @ docker pull" error && fail=t)
[ -z $fail ]
docker tag $JOB_IMAGE $ECS_IMAGE_ARN 1>&2 || (log "failed @ docker tag" error && fail=t)
[ -z $fail ]

aws ecr get-login-password | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$aws_region.amazonaws.com 1>&2 || (log "failed @ docker login" error && fail=t)
[ -z $fail ]
docker push $ECS_IMAGE_ARN 1>&2 || (log "failed @ docker push" error && fail=t)
[ -z $fail ]

log "IMAGE NAME: $image_name" info
echo $image_name