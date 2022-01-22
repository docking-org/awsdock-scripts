role_name=$1
env_suffix=$(echo $role_name | cut -d'-' -f2-)

user_id=$(aws sts get-caller-identity | jq -r '.UserId')

for p in $(aws iam list-attached-role-policies --role-name $role_name | jq -r '.AttachedPolicies[].PolicyArn'); do
	aws iam detach-role-policy --role-name $role_name --policy-arn $p
done

aws iam remove-role-from-instance-profile --role-name $role_name --instance-profile-name $role_name
aws iam delete-instance-profile --instance-profile-name $role_name
aws iam delete-role --role-name $role_name

aws iam delete-policy --policy-arn arn:aws:iam::$user_id:policy/s3Policy-input-$env_suffix
aws iam delete-policy --policy-arn arn:aws:iam::$user_id:policy/s3Policy-output-$env_suffix
