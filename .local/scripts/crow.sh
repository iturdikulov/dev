#!/bin/sh

qdbus io.crow_translate.CrowTranslate /io/crow_translate/CrowTranslate/MainWindow translateSelection
jump_app.sh crow io.crow_translate.CrowTranslate /usr/bin/crow
