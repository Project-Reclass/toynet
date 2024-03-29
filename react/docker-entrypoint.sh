#!/bin/sh

defaultCurrURI=https://raw.githubusercontent.com/Project-Reclass/toynet-content/main

if [ -z ${SERVER_URI+x} ]; then echo "SERVER_URI needs to be set"; exit 1 ; else echo "SERVER_URI is set to '$SERVER_URI'"; fi

if [ -z ${CURRICULUM_URI+x} ]; then echo "CURRICULUM_URI not set. Defaulting to $defaultCurrURI"; export CURRICULUM_URI=${defaultCurrURI}; else echo "CURRICULUM_URI is et to '$CURRICULUM_URI'"; fi

envsubst '\${CURRICULUM_URI},\${SERVER_URI}' < http.conf > /etc/nginx/conf.d/default.conf

cat /etc/nginx/conf.d/default.conf

nginx -t
exec nginx -g 'daemon off;'
