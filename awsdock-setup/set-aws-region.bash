BINDIR=$(dirname $0)
BINDIR=${BINDIR-.}
export BINDIR
source $BINDIR/common.bash

set -e

while [ -z ]; do
	# set environment region
	curr_region=$(aws configure get region)
	prompt_or_override "Which region is this environment based in? [default: $curr_region]: " aws_region AWS_REGION curr_region && OVERRIDE=TRUE || printf ""
	okay=false
	for region in $(aws ec2 describe-regions | jq -r '.Regions[].RegionName'); do
		if [ "$region" = "$aws_region" ]; then
			okay=true
			break
		fi
	done
	if [ "$okay" = "false" ]; then
		echo "That region does not exist! Try again."
		! [ -z $OVERRIDE ] && exit 1
		continue
	fi
	[ "$curr_region" != "$aws_region" ] && aws configure set region $aws_region || printf ""
	exit 0
done