#!/usr/bin/env bash
echo $PGHOST
psql -f db_matches/crsp_link.sql
