#!/bin/sh

if pgrep -x "crow" > /dev/null
then
    ww.sh -f io.crow_translate.CrowTranslate -c crow &
    qdbus io.crow_translate.CrowTranslate /io/crow_translate/CrowTranslate/MainWindow translateSelection &
else
    crow &
    sleep 1
    qdbus io.crow_translate.CrowTranslate /io/crow_translate/CrowTranslate/MainWindow translateSelection &
    ww.sh -f io.crow_translate.CrowTranslate -c crow &
fi
