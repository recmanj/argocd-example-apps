#!/bin/bash

docker network create kind-shared 

for env in dev staging prod;
	do
		kind create cluster -n $env --config kind-$env.yaml;
		docker network connect kind-shared $env-control-plane;
	done

