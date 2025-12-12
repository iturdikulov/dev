#!/bin/sh

ww.sh -t -f io.crow_translate.CrowTranslate -c "crow"

qdbus io.crow_translate.CrowTranslate /io/crow_translate/CrowTranslate/MainWindow translateSelection
