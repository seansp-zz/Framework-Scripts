#!/bin/bash
wget https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/2.2/swarm-client-2.2-jar-with-dependencies.jar -O swarm-client.jar
echo "Connecting to $1"
java -jar ./swarm-client.jar  -executors 2 -master $1 -labels test 
