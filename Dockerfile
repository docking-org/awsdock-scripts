FROM ubuntu:20.04

LABEL maintainer="Benjamin Tingle <ben@tingle.org>"

WORKDIR /tmp

# one liner to install docker
# also include aws cli dependencies (as well as vim, so people can use a text editor within the image)
RUN DEBIAN_FRONTEND=noninteractive TZ="America/New_York" apt-get update
RUN DEBIAN_FRONTEND=noninteractive TZ="America/New_York" apt-get install -qy curl lxc iptables jq unzip less groff vim unzip
RUN curl -sSL https://get.docker.com/ | sh

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
RUN unzip "/tmp/awscliv2.zip"
RUN /tmp/aws/install
RUN mkdir /home/awsuser

COPY aws-setup/bin/* /home/awsuser/aws-setup/
COPY awsdock /home/awsuser/awsdock

WORKDIR /home/awsuser
CMD ["bash"]
