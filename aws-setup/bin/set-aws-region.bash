BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash


set -e

while [ -z ]; do
	# set environment region
	curr_region=$(aws configure get region) || curr_region=
	prompt_or_override "Which region is this environment based in? [default: $curr_region]: " aws_region AWS_REGION $curr_region && OVERRIDE=TRUE || printf ""
	[ -z $AWS_REGION ] && AWS_REGION=us-west-1
	#echo "test2" "a"$aws_region "b"$curr_region "c"$AWS_REGION 1>&2
	okay=false
	for region in $(aws ec2 describe-regions | jq -r '.Regions[].RegionName'); do
		if [ "$region" = "$aws_region" ]; then
			okay=true
			break
		fi
	done
	#echo "test3" 1>&2
	if [ "$okay" = "false" ]; then
		log "That region does not exist!" error 1>&2
		aws_region=
		! [ -z $OVERRIDE ] && exit 1
		continue
	fi
	#echo "test4" 1>&2
	echo $aws_region
	[ "$curr_region" != "$aws_region" ] && aws configure set region $aws_region || printf ""
	exit 0
done