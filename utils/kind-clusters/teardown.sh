#!/bin/bash


for env in dev staging prod;
	do
		kind delete cluster -n $env;
	done

docker network rm -f kind-shared 
