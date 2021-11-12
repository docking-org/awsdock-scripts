#!/bin/bash

if [ "$1" == "help" ]; then

    echo "usage: supersub_aws_dock.bash [init|help]"
    echo "init: re-initializes static variables for this script that don't change between runs"
    echo "these include the job queue name, the job definition name, and the writable directory to put small temporary files"
    exit 0

fi

if [ "$1" == "init" ] || ! [ -f ~/.docksub_config.txt ]; then

    echo "you have not initialized your profile- please specify the following parameters:"

    while [ -z ]; do
        read -p "job queue name: " job_queue_name
        t=$(aws batch describe-job-queues --output json | grep jobQueueName | grep -w $job_queue_name | wc -l)
        if [ $t -eq 0 ]; then
            echo "job queue not found! Try again."
            continue
        fi
        break
    done

    while [ -z ]; do
        read -p "job definition name: " job_def_name
        t=$(aws batch describe-job-definitions --output json | grep jobDefinitionName | grep -w $job_def_name | wc -l)
        if [ $t -eq 0 ]; then
            echo "job definition not found! Try again."
            continue
        fi
        break
    done

    while [ -z ]; do
        read -p "writable s3 directory for small intermediate job files (NOT output): " writable_s3
        echo "test!" > /tmp/.s3test
        aws s3 cp /tmp/.s3test $writable_s3/.s3test > /dev/null 2>&1
        t=$?
        if [ $t -ne 0 ]; then
            echo "s3 location does not exist or is not writable! Try again."
            continue
        fi
        aws s3 rm $writable_s3/.s3test > /dev/null 2>&1
        rm /tmp/.s3test
        break
    done

    read -p "use NO_ACCESS_KEY method? [y/N]: " no_access_key

    echo job_queue_name=$job_queue_name > ~/.docksub_config.txt
    echo job_def_name=$job_def_name >> ~/.docksub_config.txt
    echo writable_s3=$writable_s3 >> ~/.docksub_config.txt
    echo no_access_key=$no_access_key >> ~/.docksub_config.txt

    if [ "$1" == "init" ]; then
        exit 0
    fi

fi

source ~/.docksub_config.txt

while [ -z ]; do

    read -p "specify input file (s3 or local) with list of all db2.tgz files to be evaluated: " input_file

    timestamp=$(date +%s)
    if [[ $input_file == s3://* ]]; then
	aws s3 cp $input_file /tmp/jobsub_dock_input.$timestamp > /dev/null 2>&1
	t=$?
	if [ $t -ne 0 ]; then
	    echo "s3 input_file location does not exist or is not readable! Try again."
	    continue
	fi
	break
    else
	if ! [ -f $input_file ]; then
	    echo "input_file location does not exist or is not readable! Try gain."
            continue
	fi
	cp $input_file /tmp/jobsub_dock_input.$timestamp
        break
    fi

done

read -p "specify a name for this batch job: " batch_name
echo "job files will be written to $writable_s3/$batch_name"

while [ -z ]; do
    read -p "specify a writable s3 output directory for results: " s3_output
    echo > /tmp/.s3test
    aws s3 cp /tmp/.s3test $s3_output/.s3test > /dev/null 2>&1
    t=$?
    if [ $t -ne 0 ]; then
	echo "s3 location does not exist or is not writable! Try again."
	continue
    fi
    aws s3 rm $writable_s3/.s3test > /dev/null 2>&1
    rm /tmp/.s3test
    break
done

while [ -z ]; do

    read -p "specify the s3 location for the dockfiles being used in this run: " s3_dockfiles
    aws s3 cp $s3_dockfiles/INDOCK /tmp/.s3testINDOCK > /dev/null 2>&1
    t=$?
    if [ $t -ne 0 ]; then
	echo "s3 dockfiles location does not exist or does not have an INDOCK! Try again."
	continue
    fi
    rm /tmp/.s3testINDOCK
    break

done
    
mkdir /tmp/jobsub_dock_split_input.$timestamp
split --lines=10000 /tmp/jobsub_dock_input.$timestamp /tmp/jobsub_dock_split_input.$timestamp/
i=0
for f in /tmp/jobsub_dock_split_input.$timestamp/*; do
    aws s3 cp $f $writable_s3/$batch_name/$(basename $f)
    i=$((i+1))
done

read -p "created $i jobs for this batch, submit? [y/N]: " confirm

if [ "$confirm" = "y" ]; then

    for j in /tmp/jobsub_dock_split_input.$timestamp/*; do
        s=$(cat $j | wc -l)

        if [ "$no_access_key" = "y" ]; then
            additional_env={name=NO_ACCESS_KEY,value=T},
        else
            additional_env=""
        fi

        aws batch submit-job \
            --job-name ${batch_name}_$(basename $j) \
            --job-queue $job_queue_name \
            --array-properties size=$s \
            --job-definition $job_def_name \
            --container-overrides environment="[{name=S3_INPUT_LOCATION,value=$writable_s3/$batch_name/$(basename $j)},{name=S3_OUTPUT_LOCATION,value=$s3_output/$(basename $j)},{name=S3_DOCKFILES_LOCATION,value=$s3_dockfiles},$additional_env{name=SHRTCACHE,value=/dev/shm}]"

        echo "submitted job $(basename $j), size=$s, output=$s3_output/$(basename $j), input=$writable_s3/$batch_name/$(basename $j)"
    done
    echo "done submitting jobs"

else

    aws s3 rm --recursive $writable_s3/$batch_name/

fi

rm -r /tmp/jobsub_dock_input.$timestamp
rm -r /tmp/jobsub_dock_split_input.$timestamp
