#!/bin/bash

function prompt_or_override {
	prompt=$1
	varname=$2
	overridevarname=$3
	default=$4
	if ! [ -z ${!overridevarname} ]; then
		export "$varname"="${!overridevarname}"
		return 0
	fi
	while [ -z ${!varname} ]; do
		read -p "$prompt" response
		if [ -z "$response" ]; then
			! [ -z "$default" ] && response=$default
			[ -z "$default" ] && continue
		fi
		#echo "test11" 1>&2
		export "$varname"="$response"
	done
	return 1
}

function log {
	msg=$1
	flg=$2
	__LOG_FLAGS=${__LOG_FLAGS-"info error warning"}

	if [[ "$__LOG_FLAGS" == *"$flg"* ]]; then	
		printf "[$(date)][$flg]: $msg\n"
	fi
}

TEMPDIR=${TEMPDIR-/tmp}

configuration=$1
! [ -z $configuration ] && source $configuration

prompt_or_override "[ What is the full name of the environment to submit to? ]: " env_name env_name
job_queue_name=$env_name-Queue
job_def_name=$env_name-jobdef
log "environment name: $env_name, job_queue: $job_queue_name, job_def: $job_def_name" info

while [ -z ]; do
    interactive=t
    prompt_or_override "[ Which s3 location should output be sent to? ]: " writable_s3 writable_s3 && interactive=
    echo > $TEMPDIR/.s3test
    aws s3 cp $TEMPDIR/.s3test $s3_output/.s3test > /dev/null 2>&1
    t=$?
    if [ $t -ne 0 ]; then
        log "s3 location does not exist or is not writable!" error
        if [ -z $interactive ]; then
            rm $TEMPDIR/.s3test
            exit 1
        fi
        continue
    fi
    aws s3 rm $writable_s3/.s3test > /dev/null 2>&1
    rm $TEMPDIR/.s3test
    break
done

prompt_or_override "[ What is the name for this batch job? ]: " batch_name batch_name
s3_output=$writable_s3/$batch_name
log "job files will be written to $writable_s3/$batch_name" info

while [ -z ]; do
    interactive=t
    prompt_or_override "[ Provide a location in s3 for the dockfiles being used for this run ]: " s3_dockfiles s3_dockfiles && interactive=
    aws s3 cp $s3_dockfiles/INDOCK $TEMPDIR/.s3testINDOCK > /dev/null 2>&1
    t=$?
    if [ $t -ne 0 ]; then
	    log "s3 dockfiles location does not exist or does not have an INDOCK!" error
        if [ -z $interactive ]; then
            rm $TEMPDIR/.s3testINDOCK
            exit 1
        fi
	    continue
    fi
    rm $TEMPDIR/.s3testINDOCK
    break

done

log "splitting input @ $TEMPDIR/jobsub_dock_split_input.$timestamp" info
mkdir $TEMPDIR/jobsub_dock_split_input.$timestamp
split --lines=10000 $TEMPDIR/jobsub_dock_input.$timestamp $TEMPDIR/jobsub_dock_split_input.$timestamp/
i=0
for f in $TEMPDIR/jobsub_dock_split_input.$timestamp/*; do
    aws s3 cp $f $s3_output/input/$(basename $f)
    i=$((i+1))
done

prompt_or_override "created $i jobs for this batch, submit? [y/N]: " confirm confirm

if [ "$confirm" = "y" ]; then
    for j in $TEMPDIR/jobsub_dock_split_input.$timestamp/*; do
        s=$(cat $j | wc -l)

        # outdated bit of configuration from when we hadn't nailed down the system as much
        # including it just so things don't break
        additional_env={name=NO_ACCESS_KEY,value=T},

        aws batch submit-job \
            --job-name ${batch_name}_$(basename $j) \
            --job-queue $job_queue_name \
            --array-properties size=$s \
            --job-definition $job_def_name \
            --container-overrides environment="[{name=S3_INPUT_LOCATION,value=$s3_output/input/$(basename $j)},{name=S3_OUTPUT_LOCATION,value=$s3_output/output/$(basename $j)},{name=S3_DOCKFILES_LOCATION,value=$s3_dockfiles},$additional_env{name=SHRTCACHE,value=/dev/shm}]"

        log "submitted job $(basename $j), size=$s, output=$s3_output/output/$(basename $j), input=$s3_output/input/$(basename $j)" info
    done
    log "done submitting jobs" info

else

    aws s3 rm --recursive $writable_s3/$batch_name/

fi

rm -r $TEMPDIR/jobsub_dock_input.$timestamp
rm -r $TEMPDIR/jobsub_dock_split_input.$timestamp
