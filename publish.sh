#!/bin/sh

OUT=../brainstream.github.io/

bundle exec jekyll build
rm -rf $OUT/assets
rm -rf $OUT/*.html
rm -rf $OUT/*.xml
rm -rf $OUT/*.ico
cp -rf _site/* ../brainstream.github.io/
