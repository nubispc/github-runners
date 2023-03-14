#!/bin/bash

if [ $(uname -m) == "x86_64" ]
then
	arch=aarch64
else
	arch=x86_64
fi

for x in Dockerfile.base Dockerfile.gcc-lite Dockerfile.rust
do 
	docker build -f "$x" -t harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):$(uname -m) .  
	docker push harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):$(uname -m)
	docker manifest rm harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):generic || true
	docker manifest create harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):generic --amend harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):$(uname -m) --amend harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):$arch
	docker manifest push harbor.nbfc.io/nubificus/gh-actions-runner-$(echo $x | awk -F\. '{print $2}'):generic || true
done

