# if docker daemon is running on the same machine this script is running from
if [ -e /var/run/docker.sock ]; then

	docker run -v /var/run/docker.sock:/var/run/docker.sock -it btingle/awsdock-setup

# if docker daemon is running on a different machine than the one this script is being executed on (e.g WSL)
elif ! [ -z "$DOCKER_HOST" ]; then

	host=$(basename $DOCKER_HOST | cut -d':' -f1)
	port=$(basename $DOCKER_HOST | cut -d':' -f2)
	prot=$(dirname $DOCKER_HOST)

	if [ "$host" = "localhost" ] || [ "$host" == "127.0.0.1" ]; then
		host=host.docker.internal
	fi

	# essentially we are just forwarding the DOCKER_HOST information to the container (making sure to use host.docker.internal if DOCKER_HOST is localhost)
	docker run --env DOCKER_HOST=$prot//$host:$port -it btingle/awsdock-setup

else

	echo "Docker daemon is not running on this machine and a remote DOCKER_HOST has not been specified. Check that you have DOCKER_HOST specified OR that /var/run/docker.sock exists."

fi