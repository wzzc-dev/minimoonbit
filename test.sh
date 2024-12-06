#!/bin/bash

moon run src/bin/main.mbt -- --end-stage parse $1
moon run src/bin/main.mbt -- --end-stage typecheck $1
moon run src/bin/main.mbt -- --knf-interpreter $1
moon run src/bin/main.mbt -- --closure-interpreter $1