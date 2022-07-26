set -e

region=$1

for vpc in $(aws ec2 describe-vpcs | jq -r '.Vpcs[] | .CidrBlock + "____" + .VpcId'); do
        vpcblock=$(printf $vpc | sed 's/____/ /g' | awk '{print $1}')
        vpcid=$(printf $vpc | sed 's/____/ /g' | awk '{print $2}')
        if [ "$vpcblock" = "172.31.0.0/16" ]; then
                break
        fi
        vpcid=""
done

if [ -z "$vpcid" ]; then
        vpcid=$(aws ec2 create-vpc \
                --cidr-block 172.31.0.0/16 | jq -r '.Vpc.VpcId')
fi

existing_subnet_azones_vpcs=$(aws ec2 describe-subnets | jq -r '.Subnets[] | .AvailabilityZoneId + "____" + .VpcId + "____" + .SubnetId')
function check_subnet_zone_exists {
        vpc=$1
        azone=$2
        for subnet in $existing_subnet_azones_vpcs; do
                zone=$(echo $subnet | sed 's/____/ /g' | awk '{print $1}')
                vpcid=$(echo $subnet | sed 's/____/ /g' | awk '{print $2}')
                subnetid=$(echo $subnet | sed 's/____/ /g' | awk '{print $3}')
                if [ "$vpc" = "$vpcid" ] && [ "$azone" = "$zone" ]; then
                        echo $subnetid
                        return 0
                fi
        done
        return 1
}

availability_zones=$(aws ec2 describe-availability-zones --region $region | jq -r '.AvailabilityZones[].ZoneId')

for zone in $availability_zones; do
        subnetid=$(check_subnet_zone_exists $vpcid $zone)
        if [ -z $subnetid ]; then
                subnetid=$(aws ec2 create-subnet \
                        --vpc-id $vpcid \
                        --cidr-block 172.31.16.0/20 \
                        --availability-zone-id $zone | jq -r '.SubnetId')
        fi
        echo $subnetid
done

# can't believe I have to create all this bs to make a compute environment
# you'd think they would allow for a default value like when you create one in the wizard...
sgroupid=""
for group in $(aws ec2 describe-security-groups | jq -r '.SecurityGroups[] | .GroupId + "____" + .VpcId'); do
	gid=$(echo $group | sed 's/____/ /g' | awk '{print $1}')
	vpc=$(echo $group | sed 's/____/ /g' | awk '{print $2}')
	if [ $vpc = $vpcid ]; then
		sgroupid=$gid
	fi
done

if [ -z $sgroupid ]; then
	sgroupid=$(aws ec2 create-security-group \
		--description "security group for vpc" \
		--group-name "batch-setup-security-group" \
		--vpc-id $vpcid | jq -r '.GroupId')
fi
echo $sgroupid