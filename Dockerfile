FROM oraclelinux:8

LABEL maintainer="Benjamin Tingle <ben@tingle.org>"

WORKDIR /tmp

# one liner to install docker
# also include aws cli dependencies (as well as vim, so people can use a text editor within the image)
# RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ="America/New_York"    apt-get install -qy curl lxc iptables jq unzip less groff vim unzip &&     curl -sSL https://get.docker.com/ | sh # buildkit

RUN yum install -y zip unzip
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
RUN unzip "/tmp/awscliv2.zip"
RUN /tmp/aws/install
RUN mkdir /home/awsuser

COPY aws-setup/bin/* /home/awsuser/aws-setup/
COPY awsdock /home/awsuser/awsdock

WORKDIR /home/awsuser
CMD ["bash"]
