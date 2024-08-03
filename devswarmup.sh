#!/bin/sh
 
docker build -t hello_app:0.3.0 .
docker swarm init --advertise-addr 127.0.0.1 --listen-addr 127.0.0.1 
docker stack deploy -c docker-compose.yml hello_app --with-registry-auth

read -p "Press [Enter] key to leave the swarm..."

docker swarm leave -f