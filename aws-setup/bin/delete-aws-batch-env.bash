#!/bin/bash

# ugly script to delete all components associated with a batch env
# should be fine to run in part, cancel, and run again, it will just give some ugly output instead of nice warnings.

BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

region=$(aws configure get region)
env_name=$1

[[ $env_name == *$region* ]] || (echo "change your region to the one your environment is located! use aws configure set <region code>" && exit 1)

# this bit may require running multiple times to work
log "{1} deleting aws batch components"

queuename="$env_name-Queue"
cename="$env_name-CE"
aws batch update-job-queue --job-queue $queuename --state DISABLED
aws batch delete-job-queue --job-queue $queuename
aws batch update-compute-environment --compute-environment $cename --state DISABLED
aws batch delete-compute-environment --compute-environment $cename
for jobdefarn in $(aws batch describe-job-definitions | jq -r '.jobDefinitions[] | .jobDefinitionArn' | grep $env_name); do
    aws batch deregister-job-definition --job-definition $jobdefarn
done
aws ec2 delete-launch-template --launch-template-name $env_name-LT-EBS

log "{2} deleting instance profile and role"

rolename="ecsInstanceProfile-$env_name"
aws iam delete-instance-profile --instance-profile-name $rolename
aws iam delete-role --role-name $rolename

log "{3} deleting s3 policies"
for policyarn in $(aws iam list-policies | jq -r '.Policies[] | .PolicyArn' | grep $env_name); do
    aws iam delete-policy --policy-arn $policyarn
done

log "{4} deleting repositories"
for repository in $(aws ecr describe-repositories | jq -r '.repositories[] | .repositoryName'); do
    aws ecr delete-repository --repository-name $repository
done

log "all done!"

