#!/bin/bash

# ugly script to delete all components associated with a batch env
# should be fine to run in part, cancel, and run again, it will just give some ugly output instead of nice warnings.

BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

export __LOG_FLAGS=${__LOG_FLAGS-"info warning error debug"}

region=$(aws configure get region)
region=${region-$AWS_DEFAULT_REGION}
[ -z $region ] && log "set your region with aws configure!" error && exit 1

env_name=$1

if ! [[ "$env_name" == *$region* ]]; then
    log "change your region to the one your environment is located in!" error
    exit 1
fi

# this bit may require running multiple times to work
log "{1} deleting aws batch components" info

queuename="$env_name-Queue"
cename="$env_name-CE"

log "{1.1} disabling job queue" debug
cmd="aws batch update-job-queue --job-queue $queuename --state DISABLED"
case $(aws_cmd_handler "$cmd" ClientException) in
    ClientException)
        log "job queue does not exist!" warning
    ;;
    ERROR)
        exit 1
    ;;
esac

log "{1.2} deleting job queue" debug
timeout=10
t=0
cmd="aws batch delete-job-queue --job-queue $queuename"
while true; do
    case $(aws_cmd_handler "$cmd" ClientException) in
        ClientException)
            sleep 3
            t=$((t+1))
            if [ $t -gt $timeout ]; then
                log "timed out: failed to delete job queue" error
                break
            fi
        ;;
        OK)
            break
        ;;
        ERROR)
            exit 1
        ;;
    esac
done

log "{1.3} disabling compute environment" debug

cmd="aws batch update-compute-environment --compute-environment $cename --state DISABLED"
case $(aws_cmd_handler "$cmd" ClientException) in
    ClientException)
        log "compute environment does not exist" warning
    ;;
    ERROR)
        exit 1
    ;;
esac

log "{1.4} deleting compute environment" debug 

cmd="aws batch delete-compute-environment --compute-environment $cename"
while true; do
    case $(aws_cmd_handler "$cmd" ClientException) in
        ClientException)
            sleep 3
            t=$((t+1))
            if [ $t -gt $timeout ]; then
                log "timed out: failed to delete compute environment" error
                break
            fi
        ;;
        OK)
            break
        ;;
        ERROR)
            exit 1
        ;;
    esac
done

log "{1.5} deregistering job definitions" debug

for jobdefarn in $(aws batch describe-job-definitions | jq -r '.jobDefinitions[] | .jobDefinitionArn' | grep $env_name); do
    # don't need to do any error handling here
    aws batch deregister-job-definition --job-definition $jobdefarn
done

cmd="aws ec2 delete-launch-template --launch-template-name $env_name-LT-EBS"
case $(aws_cmd_handler "$cmd" InvalidLaunchTemplateName.NotFoundException) in
    NoSuchEntity)
        log "launch template does not exist" warning
    ;;
    ERROR)
        exit 1
    ;;
esac

log "{2} deleting instance profile and role" info

rolename="ecsInstanceRole-$env_name"

cmd="aws iam remove-role-from-instance-profile --instance-profile-name $rolename --role-name $rolename"
case $(aws_cmd_handler "$cmd" NoSuchEntity) in
    NoSuchEntity)
        true
    ;;
    ERROR)
        exit 1
    ;;
esac

for policyarn in $(aws iam list-attached-role-policies --role-name $rolename | jq -r '.AttachedPolicies[] | .PolicyArn'); do
    cmd="aws iam detach-role-policy --role-name $rolename --policy-arn $policyarn"
    case $(aws_cmd_handler "$cmd") in
        ERROR)
            exit 1
        ;;
    esac
done

cmd="aws iam delete-role --role-name $rolename"
case $(aws_cmd_handler "$cmd" NoSuchEntity) in
    NoSuchEntity)
        log "instance role does not exist" warning
    ;;
    ERROR)
        exit 1
    ;;
esac

cmd="aws iam delete-instance-profile --instance-profile-name $rolename"
case $(aws_cmd_handler "$cmd" NoSuchEntity) in
    NoSuchEntity)
        log "instance profile does not exist" warning
    ;;
    ERROR)
        exit 1
    ;;
esac

log "{3} deleting s3 policies" info
for policyarn in $(aws iam list-policies | jq -r '.Policies[] | .Arn' | grep $env_name); do
    aws iam delete-policy --policy-arn $policyarn
done

log "{4} deleting repositories" info
for repository in $(aws ecr describe-repositories | jq -r '.repositories[] | .repositoryName' | grep $env_name); do

    image_digests=$(aws ecr describe-images --repository-name $repository | jq -r '.imageDetails[] | .imageDigest')
    image_digests_string=""
    for image in $image_digests; do
        image_digests_string="$image_digests_string imageDigest=$image"
    done
    image_digests_string=$(echo $image_digests_string | tr ' ' ',')

    cmd="aws ecr batch-delete-image --repository-name $repository --image-ids $image_digests_string"
    case $(aws_cmd_handler "$cmd") in
        ERROR)
            exit 1
        ;;
    esac

    cmd="aws ecr delete-repository --repository-name $repository"
    case $(aws_cmd_handler "$cmd") in
        ERROR)
            exit 1
        ;;
    esac
done

log "all done!" info