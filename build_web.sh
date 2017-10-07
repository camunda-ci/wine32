#!/bin/bash

# Build web site
mkdir -p public/7/i386
ruby build_web.rb

# Copy other web assets
cp theme.css public
cp favicon.png public
echo "$GPG_PUBLIC_KEY" > public/RPM-GPG-KEY-harbottle

# Install 3rd-party web assets
cp bower.json public
pushd public
  bower --allow-root install
popd
