# This file is part of Toynet-Flask.
#
# Toynet-Flask is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Toynet-Flask is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Toynet-Flask.  If not, see <https://www.gnu.org/licenses/>.

# MODIFIED from github user: iwaseyusuke
# link to original work: 
# https://github.com/iwaseyusuke/docker-mininet/blob/master/Dockerfile
# Commit ID: 32aa41703aeec83f044b4bbbe8daa798458034c7
# Apache License v2.0
# FROM iwaseyusuke/mininet
# Run command
# 
# 	-v <XML File Path>:/root/toynet-mininet/topo.xml #mounts the <XML File Path> to /root/toynet-mininet/topo.xml on the container
FROM python:3.8-slim-buster

USER root
WORKDIR /root

RUN apt-get -y update && apt-get install -y apt-transport-https
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    iproute2 \
    iputils-ping \
    mininet \
    net-tools \
    openvswitch-switch \
    openvswitch-testcontroller \
    gcc \
    python3-dev \
    python3-pip \
    libffi-dev \
 && rm -rf /var/lib/apt/lists/* 

EXPOSE 5000 

ENV FLASK_APP=flasksrc
ENV FLASK_ENV=development
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

WORKDIR /root/toynet/flask/toynet_mininet
COPY requirements.txt .
RUN pip3 install --upgrade pip
RUN pip3 install --upgrade setuptools
RUN pip3 install -r requirements.txt 

COPY . . 
RUN chmod +x /root/toynet/flask/toynet_mininet/*.sh

ENTRYPOINT ["/root/toynet/flask/toynet_mininet/entrypoint.sh"]
