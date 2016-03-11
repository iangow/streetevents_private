#!/usr/bin/env bash
rsync -avz researchgrid.hbs.edu:/export/projects/streetevents_project/ \
    $EDGAR_DIR/streetevents_project/ --include=*.xml --exclude=*.zip \
    --exclude=*.7z --exclude=*.sas7bdat \
    --exclude=*.xls* --exclude=jsheridan/*

download_extract/create_call_files.R
download_extract/import_call_meta_data.R
download_extract/import_speaker_data.R