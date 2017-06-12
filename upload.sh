#!/bin/bash

package=$1
curl -k -u azure-kernel-test:8fNC7PtgNMRKf79QRq -X POST -F file=@$package https://azure-apt-cat.cloudapp.net/v1/files
